// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:analyzer/analyzer.dart';
import 'package:barback/barback.dart';
import 'package:bazel_worker/bazel_worker.dart';
import 'package:cli_util/cli_util.dart' as cli_util;
import 'package:path/path.dart' as p;

import '../../dart.dart';
import '../../io.dart';
import 'module_reader.dart';
import 'scratch_space.dart';
import 'summaries.dart';
import 'workers.dart';

/// Returns whether or not [dartId] is an app entrypoint (basically, whether or
/// not it has a `main` function).
Future<bool> isAppEntryPoint(
    AssetId dartId, Future<Asset> getAsset(AssetId id)) async {
  assert(dartId.extension == '.dart');
  var dartAsset = await getAsset(dartId);
  // Skip reporting errors here, dartdevc will report them later with nicer
  // formatting.
  var parsed = parseCompilationUnit(await dartAsset.readAsString(),
      suppressErrors: true);
  return isEntrypoint(parsed);
}

/// Bootstraps the JS module for the entrypoint dart file [dartEntrypointId]
/// with two additional JS files:
///
/// * A `$dartEntrypointId.js` file which is the main entrypoint for the app. It
///   injects a script tag whose src is `require.js` and whose `data-main`
///   attribute points at a `$dartEntrypointId.bootstrap.js` file.
/// * A `$dartEntrypointId.bootstrap.js` file which invokes the top level `main`
///   function from the entrypoint module, after performing some necessary SDK
///   setup.
///
/// In debug mode an empty sourcemap will be output for the entrypoint JS file
/// to satisfy the test package runner (there is no original dart file to map it
/// back to though).
///
/// Synchronously returns a `Map<AssetId, Future<Asset>>` so that you can know
/// immediately what assets will be output.
Map<AssetId, Future<Asset>> bootstrapDartDevcEntrypoint(
    AssetId dartEntrypointId,
    BarbackMode mode,
    ModuleReader moduleReader,
    Future<Asset> getAsset(AssetId id)) {
  var bootstrapId = dartEntrypointId.addExtension('.bootstrap.js');
  var jsEntrypointId = dartEntrypointId.addExtension('.js');
  var jsMapEntrypointId = jsEntrypointId.addExtension('.map');

  var outputCompleters = <AssetId, Completer<Asset>>{
    bootstrapId: new Completer(),
    jsEntrypointId: new Completer(),
  };
  if (mode == BarbackMode.DEBUG) {
    outputCompleters[jsMapEntrypointId] = new Completer<Asset>();
  }

  return _ensureComplete(outputCompleters, () async {
    var module = await moduleReader.moduleFor(dartEntrypointId);
    if (module == null) return;

    // The path to the entrypoint JS module as it should appear in the call to
    // `require` in the bootstrap file.
    var moduleDir = topLevelDir(dartEntrypointId.path);
    var appModulePath = p.url.relative(p.url.join(moduleDir, module.id.name),
        from: p.url.dirname(dartEntrypointId.path));

    // The name of the entrypoint dart library within the entrypoint JS module.
    //
    // This is used to invoke `main()` from within the bootstrap script.
    //
    // TODO(jakemac53): Sane module name creation, this only works in the most
    // basic of cases.
    //
    // See https://github.com/dart-lang/sdk/issues/27262 for the root issue
    // which will allow us to not rely on the naming schemes that dartdevc uses
    // internally, but instead specify our own.
    var appModuleScope = p.url
        .split(p.url.withoutExtension(
            p.url.relative(dartEntrypointId.path, from: moduleDir)))
        .join("__")
        .replaceAll('.', '\$46');

    // Modules not under a `packages` directory need custom module paths.
    var customModulePaths = <String>[];
    var transitiveDeps = await moduleReader.readTransitiveDeps(module);
    for (var dep in transitiveDeps) {
      if (dep.dir != 'lib') {
        customModulePaths.add('"${dep.dir}/${dep.name}": "${dep.name}"');
      }
    }

    var bootstrapContent = '''
require.config({
    waitSeconds: 30,
    paths: {
      ${customModulePaths.join(',\n      ')}
    }
});

require(["$appModulePath", "dart_sdk"], function(app, dart_sdk) {
  dart_sdk._isolate_helper.startRootIsolate(() => {}, []);
  app.$appModuleScope.main();
});
''';
    outputCompleters[bootstrapId]
        .complete(new Asset.fromString(bootstrapId, bootstrapContent));

    var bootstrapModuleName = p.withoutExtension(
        p.relative(bootstrapId.path, from: p.dirname(dartEntrypointId.path)));
    var entrypointJsContent = '''
var el = document.createElement("script");
el.defer = true;
el.async = false;
el.src = "require.js";
el.setAttribute("data-main", "$bootstrapModuleName");
document.head.appendChild(el);
''';
    outputCompleters[jsEntrypointId]
        .complete(new Asset.fromString(jsEntrypointId, entrypointJsContent));

    if (mode == BarbackMode.DEBUG) {
      outputCompleters[jsMapEntrypointId].complete(new Asset.fromString(
          jsMapEntrypointId,
          '{"version":3,"sourceRoot":"","sources":[],"names":[],"mappings":"",'
          '"file":""}'));
    }
  });
}

/// Compiles [module] using the `dartdevc` binary from the SDK to a relative
/// path under the package that looks like `$outputDir/${module.id.name}.js`.
///
/// Synchronously returns a `Map<AssetId, Future<Asset>>` so that you can know
/// immediately what assets will be output.
Map<AssetId, Future<Asset>> createDartdevcModule(
    AssetId id,
    ModuleReader moduleReader,
    ScratchSpace scratchSpace,
    Map<String, String> environmentConstants,
    BarbackMode mode,
    logError(String message)) {
  assert(id.extension == '.js');
  var outputCompleters = <AssetId, Completer<Asset>>{
    id: new Completer(),
  };
  if (mode == BarbackMode.DEBUG) {
    outputCompleters[id.addExtension('.map')] = new Completer();
  }

  return _ensureComplete(outputCompleters, () async {
    var module = await moduleReader.moduleFor(id);
    if (module == null) return;
    var transitiveModuleDeps = await moduleReader.readTransitiveDeps(module);
    var linkedSummaryIds =
        transitiveModuleDeps.map((depId) => depId.linkedSummaryId).toSet();
    var allAssetIds = new Set<AssetId>()
      ..addAll(module.assetIds)
      ..addAll(linkedSummaryIds);
    await scratchSpace.ensureAssets(allAssetIds);
    var jsOutputFile = scratchSpace.fileFor(module.id.jsId);
    var sdk_summary = p.url.join(sdkDir.path, 'lib/_internal/ddc_sdk.sum');
    var request = new WorkRequest();
    request.arguments.addAll([
      '--dart-sdk-summary=$sdk_summary',
      // TODO(jakemac53): Remove when no longer needed,
      // https://github.com/dart-lang/pub/issues/1583.
      '--unsafe-angular2-whitelist',
      '--modules=amd',
      '--dart-sdk=${sdkDir.path}',
      '--module-root=${scratchSpace.tempDir.path}',
      '--library-root=${p.dirname(jsOutputFile.path)}',
      '--summary-extension=${linkedSummaryExtension.substring(1)}',
      '--no-summarize',
      '-o',
      jsOutputFile.path,
    ]);

    if (mode == BarbackMode.RELEASE) {
      request.arguments.add('--no-source-map');
    }

    // Add environment constants.
    environmentConstants.forEach((key, value) {
      request.arguments.add('-D$key=$value');
    });

    // Add all the linked summaries as summary inputs.
    for (var id in linkedSummaryIds) {
      request.arguments.addAll(['-s', scratchSpace.fileFor(id).path]);
    }

    // Add URL mappings for all the package: files to tell DartDevc where to
    // find them.
    for (var id in module.assetIds) {
      var uri = canonicalUriFor(id);
      if (uri.startsWith('package:')) {
        request.arguments
            .add('--url-mapping=$uri,${scratchSpace.fileFor(id).path}');
      }
    }
    // And finally add all the urls to compile, using the package: path for
    // files under lib and the full absolute path for other files.
    request.arguments.addAll(module.assetIds.map((id) {
      var uri = canonicalUriFor(id);
      if (uri.startsWith('package:')) {
        return uri;
      }
      return scratchSpace.fileFor(id).path;
    }));

    var response = await dartdevcDriver.doWork(request);

    // TODO(jakemac53): Fix the ddc worker mode so it always sends back a bad
    // status code if something failed. Today we just make sure there is an output
    // JS file to verify it was successful.
    if (response.exitCode != EXIT_CODE_OK || !jsOutputFile.existsSync()) {
      logError('Error compiling dartdevc module: ${module.id}.\n'
          '${response.output}');
    } else {
      outputCompleters[module.id.jsId].complete(
          new Asset.fromBytes(module.id.jsId, jsOutputFile.readAsBytesSync()));
      if (mode == BarbackMode.DEBUG) {
        var sourceMapFile = scratchSpace.fileFor(module.id.jsSourceMapId);
        outputCompleters[module.id.jsSourceMapId].complete(new Asset.fromBytes(
            module.id.jsSourceMapId, sourceMapFile.readAsBytesSync()));
      }
    }
  });
}

/// Copies the `dart_sdk.js` and `require.js` AMD files from the SDK into
/// [outputDir].
///
/// Returns a `Map<AssetId, Asset>` of the created assets.
Map<AssetId, Asset> copyDartDevcResources(String package, String outputDir) {
  var sdk = cli_util.getSdkDir();
  var outputs = <AssetId, Asset>{};

  // Copy the dart_sdk.js file for AMD into the output folder.
  var sdkJsOutputId =
      new AssetId(package, p.url.join(outputDir, 'dart_sdk.js'));
  var sdkAmdJsPath = p.url.join(sdk.path, 'lib/dev_compiler/amd/dart_sdk.js');
  outputs[sdkJsOutputId] =
      new Asset.fromFile(sdkJsOutputId, new File(sdkAmdJsPath));

  // Copy the require.js file for AMD into the output folder.
  var requireJsPath = p.url.join(sdk.path, 'lib/dev_compiler/amd/require.js');
  var requireJsOutputId =
      new AssetId(package, p.url.join(outputDir, 'require.js'));
  outputs[requireJsOutputId] =
      new Asset.fromFile(requireJsOutputId, new File(requireJsPath));

  return outputs;
}

/// Runs [fn], and then ensures that all [completers] are completed.
///
/// If an error is caught, then all [completers] that weren't completed are
/// completed with that error and stack trace.
///
/// If no error was caught then all [completers] that weren't completed are
/// completed with an [AssetNotFoundException].
///
/// Synchronously returns a `Map<AssetId, Future<Asset>` which is derived from
/// the original [completers].
Map<AssetId, Future<Asset>> _ensureComplete(
    Map<AssetId, Completer<Asset>> completers, Future fn()) {
  var futures = <AssetId, Future<Asset>>{};
  completers.forEach((k, v) => futures[k] = v.future);
  () async {
    try {
      await fn();
    } catch (e, s) {
      for (var completer in completers.values) {
        if (!completer.isCompleted) completer.completeError(e, s);
      }
    } finally {
      for (var id in completers.keys) {
        if (!completers[id].isCompleted) {
          completers[id].completeError(new AssetNotFoundException(id));
        }
      }
    }
  }();
  return futures;
}
