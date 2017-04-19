// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:barback/barback.dart';
import 'package:bazel_worker/bazel_worker.dart';
import 'package:path/path.dart' as p;

import 'workers.dart';
import 'module.dart';
import 'module_reader.dart';
import 'temp_environment.dart';
import 'unlinked_summary_transformer.dart';
import 'util.dart';

final String linkedSummaryExtension = '.linked.sum';

/// Creates linked analyzer summaries given [moduleConfigName] files which
/// describe a set of [Module]s.
///
/// Unlinked summaries should have already been created for all modules and will
/// be read in to create the linked summaries.
class LinkedSummaryTransformer extends Transformer {
  @override
  String get allowedExtensions => moduleConfigName;

  LinkedSummaryTransformer();

  @override
  Future apply(Transform transform) async {
    var reader = new ModuleReader(transform.readInputAsString);
    var modules = await reader.readModules(transform.primaryInput.id);
    await Future.wait(modules
        .map((m) => _createLinkedSummaryForModule(m, reader, transform)));
  }
}

Future _createLinkedSummaryForModule(
    Module module, ModuleReader reader, Transform transform) async {
  TempEnvironment tempEnv;
  try {
    // Unlinked summaries for all transitive deps.
    var unlinkedSummaryIds = (await reader.readTransitiveDeps(module)).map(
        (moduleId) => new AssetId(
            moduleId.package, '${moduleId.name}$unlinkedSummaryExtension'));
    // We need all the modules asset ids and all its dependencies unlinked
    // summary ids.
    var allAssetIds = <AssetId>[]
      ..addAll(module.assetIds)
      ..addAll(unlinkedSummaryIds);
    tempEnv = await TempEnvironment.create(allAssetIds, transform.readInput);
    var summaryOutputId = new AssetId(module.id.package,
        p.url.join('lib', '${module.id.name}$linkedSummaryExtension'));
    var summaryOutputFile = tempEnv.fileFor(summaryOutputId);
    var request = new WorkRequest();
    request.arguments.addAll([
      '--build-summary-only',
      '--build-summary-only-diet',
      '--build-summary-output=${summaryOutputFile.path}',
    ]);
    // Add all the unlinked summaries as build summary inputs.
    request.arguments.addAll(unlinkedSummaryIds
        .map((id) => '--build-summary-input=${tempEnv.fileFor(id).path}'));
    // Add all the files to include in the linked summary bundle.
    request.arguments.addAll(module.assetIds.map((id) {
      return '${canonicalUriFor(id)}|${tempEnv.fileFor(id).path}';
    }));
    var response = await analyzerDriver.doWork(request);
    if (response.exitCode == EXIT_CODE_ERROR) {
      transform.logger
          .error('Error creating linked summaries for module: ${module.id}.\n'
              '${response.output}');
    } else {
      transform.addOutput(new Asset.fromBytes(
          summaryOutputId, summaryOutputFile.readAsBytesSync()));
    }
  } finally {
    tempEnv?.delete();
  }
}
