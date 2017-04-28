// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:barback/barback.dart';
import 'package:bazel_worker/bazel_worker.dart';
import 'package:path/path.dart' as p;

import '../../io.dart';
import 'workers.dart';
import 'module.dart';
import 'module_reader.dart';
import 'temp_environment.dart';
import 'linked_summary_transformer.dart';

/// Creates dartdevc modules given [moduleConfigName] files which describe a set
/// of [Module]s.
///
/// Linked summaries should have already been created for all modules and will
/// be read in to create the modules.
class DartDevcModuleTransformer extends Transformer {
  @override
  String get allowedExtensions => moduleConfigName;

  DartDevcModuleTransformer();

  @override
  Future apply(Transform transform) async {
    TempEnvironment tempEnv;
    var reader = new ModuleReader(transform.readInputAsString);
    var modules = await reader.readModules(transform.primaryInput.id);
    try {
      var allAssetIds = new Set<AssetId>();
      var summariesForModule = <ModuleId, Set<AssetId>>{};
      for (var module in modules) {
        var transitiveModuleDeps = await reader.readTransitiveDeps(module);
        var linkedSummaryIds = transitiveModuleDeps.map((depId) {
          assert(depId.name.isNotEmpty);
          var summaryDir = depId.name.split('__').first;
          return new AssetId(depId.package,
              p.join(summaryDir, '${depId.name}$linkedSummaryExtension'));
        }).toSet();
        summariesForModule[module.id] = linkedSummaryIds;
        allAssetIds..addAll(module.assetIds)..addAll(linkedSummaryIds);
      }
      // Create a single temp environment for all the modules in this package.
      tempEnv = await TempEnvironment.create(allAssetIds, transform.readInput);
      var outputDir = topLevelDir(transform.primaryInput.id.path);
      await Future.wait(modules.map((m) => _createDartdevcModule(
          m, outputDir, tempEnv, summariesForModule[m.id], transform)));
    } finally {
      tempEnv?.delete();
    }
  }
}

/// Compiles [module] using the `dartdevc` binary from the SDK to a relative
/// path under the package that looks like `$outputDir/${module.id.name}.js`.
Future _createDartdevcModule(
    Module module,
    String outputDir,
    TempEnvironment tempEnv,
    Set<AssetId> linkedSummaryIds,
    Transform transform) async {
  var logger = transform.logger;
  var jsOutputId = new AssetId(
      module.id.package, p.url.join(outputDir, '${module.id.name}.js'));
  var jsOutputFile = tempEnv.fileFor(jsOutputId);
  var sdk_summary = p.url.join(sdkDir.path, 'lib/_internal/ddc_sdk.sum');
  var request = new WorkRequest();
  request.arguments.addAll([
    '--dart-sdk-summary=$sdk_summary',
    // TODO(jakemac53): Remove when no longer needed.
    '--unsafe-angular2-whitelist',
    '--modules=amd',
    '--dart-sdk=${sdkDir.path}',
    '--module-root=${tempEnv.tempDir.path}',
    '--library-root=${p.dirname(jsOutputFile.path)}',
    '--summary-extension=${linkedSummaryExtension.substring(1)}',
    '--unsafe-force-compile',
    '--no-summarize',
    '-o',
    jsOutputFile.path,
  ]);
  // Add all the linked summaries as summary inputs.
  for (var id in linkedSummaryIds) {
    request.arguments.addAll(['-s', tempEnv.fileFor(id).path]);
  }
  // Add url mappings for all the package: files to tell ddc where to find them.
  for (var id in module.assetIds) {
    var uri = canonicalUriFor(id);
    if (uri.startsWith('package:')) {
      request.arguments.add('--url-mapping=$uri,${tempEnv.fileFor(id).path}');
    }
  }
  // And finally add all the urls to compile, using the package: path for files
  // under lib and the full absolute path for other files.
  request.arguments.addAll(module.assetIds.map((id) {
    var uri = canonicalUriFor(id);
    if (uri.startsWith('package:')) {
      return uri;
    }
    return tempEnv.fileFor(id).path;
  }));

  var response = await dartdevcDriver.doWork(request);

  // TODO(jakemac53): Fix the ddc worker mode so it always sends back a bad
  // status code if something failed. Today we just make sure there is an output
  // js file to verify it was successful.
  if (response.exitCode != EXIT_CODE_OK || !jsOutputFile.existsSync()) {
    // We only log warnings for ddc modules because technically they don't all
    // need to compile successfully, only the ones imported by an entrypoint do.
    logger.warning('Error compiling dartdevc module: ${module.id}.\n'
        '${response.output}');
  } else {
    transform.addOutput(
        new Asset.fromBytes(jsOutputId, jsOutputFile.readAsBytesSync()));
  }
}
