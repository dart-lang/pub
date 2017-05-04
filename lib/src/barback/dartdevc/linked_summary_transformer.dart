// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:barback/barback.dart';
import 'package:bazel_worker/bazel_worker.dart';

import 'module.dart';
import 'module_reader.dart';
import 'scratch_space.dart';
import 'workers.dart';

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
    var configId = transform.primaryInput.id;
    var modules = await reader.readModules(configId);
    ScratchSpace scratchSpace;
    try {
      var allAssetIds = new Set<AssetId>();
      var summariesForModule = <ModuleId, Set<AssetId>>{};
      for (var module in modules) {
        var transitiveModuleDeps = await reader.readTransitiveDeps(module);
        var unlinkedSummaryIds = transitiveModuleDeps
            .map((depId) => depId.unlinkedSummaryId)
            .toSet();
        summariesForModule[module.id] = unlinkedSummaryIds;
        allAssetIds..addAll(module.assetIds)..addAll(unlinkedSummaryIds);
      }
      // Create a single temp environment for all the modules in this package.
      scratchSpace =
          await ScratchSpace.create(allAssetIds, transform.readInput);
      await Future.wait(modules.map((m) => _createLinkedSummaryForModule(
          m, summariesForModule[m.id], scratchSpace, transform)));
    } finally {
      scratchSpace?.delete();
    }
  }
}

Future _createLinkedSummaryForModule(
    Module module,
    Set<AssetId> unlinkedSummaryIds,
    ScratchSpace scratchSpace,
    Transform transform) async {
  var summaryOutputFile = scratchSpace.fileFor(module.id.linkedSummaryId);
  var request = new WorkRequest();
  // TODO(jakemac53): Diet parsing results in erroneous errors in later steps,
  // but ideally we would do that (pass '--build-summary-only-diet').
  request.arguments.addAll([
    '--build-summary-only',
    '--build-summary-output=${summaryOutputFile.path}',
    '--strong',
  ]);
  // Add all the unlinked summaries as build summary inputs.
  request.arguments.addAll(unlinkedSummaryIds.map((id) =>
      '--build-summary-unlinked-input=${scratchSpace.fileFor(id).path}'));
  // Add all the files to include in the linked summary bundle.
  request.arguments.addAll(module.assetIds.map((id) {
    var uri = canonicalUriFor(id);
    if (!uri.startsWith('package:')) {
      uri = 'file://$uri';
    }
    return '$uri|${scratchSpace.fileFor(id).path}';
  }));
  var response = await analyzerDriver.doWork(request);
  if (response.exitCode == EXIT_CODE_ERROR) {
    transform.logger
        .error('Error creating linked summaries for module: ${module.id}.\n'
            '${response.output}');
  } else {
    transform.addOutput(new Asset.fromBytes(
        module.id.linkedSummaryId, summaryOutputFile.readAsBytesSync()));
  }
}
