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
final String unlinkedSummaryExtension = '.unlinked.sum';

/// Creates a linked summary for [module].
///
/// [unlinkedSummaryIds] should contain unlinked summaries for all transitive
/// deps of [module], and [scratchSpace] must have those files available as well
/// as the original Dart sources for this module.
///
/// Synchronously returns a `Map<AssetId, Future<Asset>>` so that you can know
/// immediately what assets will be output.
Future<Asset> createLinkedSummary(AssetId id, ModuleReader moduleReader,
    Stream<List<int>> readAsset(AssetId), logError(String message)) async {
  assert(id.path.endsWith(linkedSummaryExtension));
  var module = await moduleReader.moduleFor(id);
  var transitiveModuleDeps = await moduleReader.readTransitiveDeps(module);
  var unlinkedSummaryIds =
      transitiveModuleDeps.map((depId) => depId.unlinkedSummaryId).toSet();
  var allAssetIds = new Set<AssetId>()
    ..addAll(module.assetIds)
    ..addAll(unlinkedSummaryIds);
  var scratchSpace = await ScratchSpace.create(allAssetIds, readAsset);
  try {
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
    request.arguments
        .addAll(_analyzerSourceArgsForModule(module, scratchSpace));
    var response = await analyzerDriver.doWork(request);
    if (response.exitCode == EXIT_CODE_ERROR) {
      logError('Error creating linked summaries for module: ${module.id}.\n'
          '${response.output}');
      return null;
    }
    return new Asset.fromBytes(
        module.id.linkedSummaryId, summaryOutputFile.readAsBytesSync());
  } finally {
    scratchSpace?.delete();
  }
}

/// Creates an unlinked summary at [id].
Future<Asset> createUnlinkedSummary(AssetId id, ModuleReader moduleReader,
    Stream<List<int>> readAsset(AssetId), logError(String message)) async {
  assert(id.path.endsWith(unlinkedSummaryExtension));
  var module = await moduleReader.moduleFor(id);
  var scratchSpace = await ScratchSpace.create(module.assetIds, readAsset);
  try {
    var summaryOutputFile = scratchSpace.fileFor(module.id.unlinkedSummaryId);
    var request = new WorkRequest();
    // TODO(jakemac53): Diet parsing results in erroneous errors later on today,
    // but ideally we would do that (pass '--build-summary-only-diet').
    request.arguments.addAll([
      '--build-summary-only',
      '--build-summary-only-unlinked',
      '--build-summary-output=${summaryOutputFile.path}',
      '--strong',
    ]);
    // Add all the files to include in the unlinked summary bundle.
    request.arguments
        .addAll(_analyzerSourceArgsForModule(module, scratchSpace));
    var response = await analyzerDriver.doWork(request);
    if (response.exitCode == EXIT_CODE_ERROR) {
      logError('Error creating unlinked summaries for module: ${module.id}.\n'
          '${response.output}');
      return null;
    }
    return new Asset.fromBytes(
        module.id.unlinkedSummaryId, summaryOutputFile.readAsBytesSync());
  } finally {
    scratchSpace?.delete();
  }
}

Iterable<String> _analyzerSourceArgsForModule(
    Module module, ScratchSpace scratchSpace) {
  return module.assetIds.map((id) {
    var uri = canonicalUriFor(id);
    if (!uri.startsWith('package:')) {
      uri = 'file:///$uri';
    }
    return '$uri|${scratchSpace.fileFor(id).path}';
  });
}
