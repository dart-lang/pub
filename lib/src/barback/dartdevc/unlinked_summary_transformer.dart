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

final String unlinkedSummaryExtension = '.unlinked.sum';

/// Creates unlinked analyzer summaries given [moduleConfigName] files which
/// describe a set of [Module]s.
class UnlinkedSummaryTransformer extends Transformer {
  @override
  String get allowedExtensions => moduleConfigName;

  UnlinkedSummaryTransformer();

  @override
  Future apply(Transform transform) async {
    var reader = new ModuleReader(transform.readInputAsString);
    var configId = transform.primaryInput.id;
    var modules = await reader.readModules(configId);
    TempEnvironment tempEnv;
    try {
      var allAssetIds = modules.fold(new Set<AssetId>(), (allAssets, module) {
        allAssets.addAll(module.assetIds);
        return allAssets;
      });
      // Create a single temp environment for all the modules in this package.
      tempEnv = await TempEnvironment.create(allAssetIds, transform.readInput);
      await Future.wait(modules.map((m) => _createUnlinkedSummaryForModule(
          m, topLevelDir(configId.path), tempEnv, transform)));
    } finally {
      tempEnv?.delete();
    }
  }
}

Future _createUnlinkedSummaryForModule(Module module, String outputDir,
    TempEnvironment tempEnv, Transform transform) async {
  var summaryOutputId = new AssetId(module.id.package,
      p.url.join(outputDir, '${module.id.name}$unlinkedSummaryExtension'));
  var summaryOutputFile = tempEnv.fileFor(summaryOutputId);
  var request = new WorkRequest();
  request.arguments.addAll([
    '--build-summary-only',
    '--build-summary-only-unlinked',
    '--build-summary-only-diet',
    '--build-summary-output=${summaryOutputFile.path}',
  ]);
  // Add all the files to include in the unlinked summary bundle.
  request.arguments.addAll(module.assetIds.map((id) {
    var uri = canonicalUriFor(id);
    if (!uri.startsWith('package:')) {
      uri = 'file://$uri';
    }
    return '$uri|${tempEnv.fileFor(id).path}';
  }));
  var response = await analyzerDriver.doWork(request);
  if (response.exitCode == EXIT_CODE_ERROR) {
    transform.logger
        .error('Error creating unlinked summaries for module: ${module.id}.\n'
            '${response.output}');
  } else {
    transform.addOutput(new Asset.fromBytes(
        summaryOutputId, summaryOutputFile.readAsBytesSync()));
  }
}
