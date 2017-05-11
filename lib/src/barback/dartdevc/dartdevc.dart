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

/// Returns whether or no [dartId] is an app entrypoint (basically, whether or
/// not it has a `main` function).
Future<bool> isAppEntryPoint(
    AssetId dartId, Future<Asset> getAsset(AssetId id)) async {
  assert(dartId.extension == '.dart');
  var dartAsset = await getAsset(dartId);
  var parsed = parseCompilationUnit(await dartAsset.readAsString(),
      suppressErrors: true);
  return isEntrypoint(parsed);
}

/// Bootstraps the js module for the entrypoint dart file [dartEntrypointId]
/// with two additional JS files:
///
/// * A `$dartEntrypointId.js` file which is the main entrypoint for the app. It
///   injects a script tag whose src is `require.js` and whose `data-main`
///   attribute points at a `$dartEntrypointId.bootstrap.js` file.
/// * A `$dartEntrypointId.bootstrap.js` file which invokes the top level `main`
///   function from the entrypoint module, after performing some necessary SDK
///   setup.
///
/// In debug mode an empty sourcemap will be output for the entrypoint js file
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
    bootstrapId: new Completer<Asset>(),
    jsEntrypointId: new Completer<Asset>(),
  };
  if (mode == BarbackMode.DEBUG) {
    outputCompleters[jsMapEntrypointId] = new Completer<Asset>();
  }

  () async {
    var module = await moduleReader.moduleFor(dartEntrypointId);

    // The path to the entrypoint js module as it should appear in the call to
    // `require` in the bootstrap file.
    var moduleDir = topLevelDir(dartEntrypointId.path);
    var appModulePath = p.relative(p.join(moduleDir, module.id.name),
        from: p.dirname(dartEntrypointId.path));

    // The name of the entrypoint dart library within the entrypoint js module.
    //
    // This is used to invoke `main()` from within the bootstrap script.
    //
    // TODO(jakemac53): Sane module name creation, this only works in the most
    // basic of cases.
    //
    // See https://github.com/dart-lang/sdk/issues/27262 for the root issue which
    // will allow us to not rely on the naming schemes that dartdevc uses
    // internally, but instead specify our own.
    var appModuleScope = p.url
        .split(p.withoutExtension(
            p.relative(dartEntrypointId.path, from: moduleDir)))
        .join("__")
        .replaceAll('.', '\$46');
    var bootstrapContent = '''
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
  }();

  var outputFutures = <AssetId, Future<Asset>>{};
  outputCompleters.forEach((k, v) => outputFutures[k] = v.future);
  return outputFutures;
}

/// Compiles [module] using the `dartdevc` binary from the SDK to a relative
/// path under the package that looks like `$outputDir/${module.id.name}.js`.
///
/// Synchronously returns a `Map<AssetId, Future<Asset>>` so that you can know
/// immediately what assets will be output.
Map<AssetId, Future<Asset>> createDartdevcModule(
    AssetId id,
    ModuleReader moduleReader,
    Stream<List<int>> readAsset(AssetId id),
    Map<String, String> environmentConstants,
    BarbackMode mode,
    logError(String message)) {
  var outputCompleters = <AssetId, Completer<Asset>>{
    id: new Completer<Asset>(),
  };
  if (mode == BarbackMode.DEBUG) {
    outputCompleters[id.addExtension('.map')] = new Completer<Asset>();
  }

  () async {
    var module = await moduleReader.moduleFor(id);
    var transitiveModuleDeps = await moduleReader.readTransitiveDeps(module);
    var linkedSummaryIds =
        transitiveModuleDeps.map((depId) => depId.linkedSummaryId).toSet();
    var allAssetIds = new Set<AssetId>()
      ..addAll(module.assetIds)
      ..addAll(linkedSummaryIds);
    var scratchSpace = await ScratchSpace.create(allAssetIds, readAsset);
    try {
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

      // Add URL mappings for all the package: files to tell DartDevc where to find
      // them.
      for (var id in module.assetIds) {
        var uri = canonicalUriFor(id);
        if (uri.startsWith('package:')) {
          request.arguments
              .add('--url-mapping=$uri,${scratchSpace.fileFor(id).path}');
        }
      }
      // And finally add all the urls to compile, using the package: path for files
      // under lib and the full absolute path for other files.
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
      // js file to verify it was successful.
      if (response.exitCode != EXIT_CODE_OK || !jsOutputFile.existsSync()) {
        logError('Error compiling dartdevc module: ${module.id}.\n'
            '${response.output}');
        outputCompleters.values.forEach((completer) {
          completer.complete(null);
        });
      } else {
        outputCompleters[module.id.jsId].complete(new Asset.fromBytes(
            module.id.jsId, jsOutputFile.readAsBytesSync()));
        if (mode == BarbackMode.DEBUG) {
          var sourceMapFile = scratchSpace.fileFor(module.id.jsSourceMapId);
          outputCompleters[module.id.jsSourceMapId].complete(
              new Asset.fromBytes(
                  module.id.jsSourceMapId, sourceMapFile.readAsBytesSync()));
        }
      }
    } finally {
      scratchSpace?.delete();
    }
  }();

  var outputFutures = <AssetId, Future<Asset>>{};
  outputCompleters.forEach((k, v) => outputFutures[k] = v.future);
  return outputFutures;
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
