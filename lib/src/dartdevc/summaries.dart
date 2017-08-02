// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:barback/barback.dart';
import 'package:bazel_worker/bazel_worker.dart';

import 'errors.dart';
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
Future<Asset> createLinkedSummary(
    AssetId id, ModuleReader moduleReader, ScratchSpace scratchSpace) async {
  assert(id.path.endsWith(linkedSummaryExtension));
  var module = await moduleReader.moduleFor(id);
  var transitiveModuleDeps = await moduleReader.readTransitiveDeps(module);
  var unlinkedSummaryIds =
      transitiveModuleDeps.map((depId) => depId.unlinkedSummaryId).toSet();
  var allAssetIds = new Set<AssetId>()
    ..addAll(module.assetIds)
    ..addAll(unlinkedSummaryIds);
  await scratchSpace.ensureAssets(allAssetIds);
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
  request.arguments.addAll(_analyzerSourceArgsForModule(module, scratchSpace));
  var response = await analyzerDriver.doWork(request);
  if (response.exitCode == EXIT_CODE_ERROR) {
    throw new AnalyzerSummaryException(
        module.id.linkedSummaryId, response.output);
  }
  return new Asset.fromBytes(
      module.id.linkedSummaryId, summaryOutputFile.readAsBytesSync());
}

/// Creates an unlinked summary at [id].
Future<Asset> createUnlinkedSummary(
    AssetId id, ModuleReader moduleReader, ScratchSpace scratchSpace) async {
  assert(id.path.endsWith(unlinkedSummaryExtension));
  var module = await moduleReader.moduleFor(id);
  await scratchSpace.ensureAssets(module.assetIds);
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
  request.arguments.addAll(_analyzerSourceArgsForModule(module, scratchSpace));
  var response = await analyzerDriver.doWork(request);
  if (response.exitCode == EXIT_CODE_ERROR) {
    throw new AnalyzerSummaryException(
        module.id.unlinkedSummaryId, response.output);
  }
  return new Asset.fromBytes(
      module.id.unlinkedSummaryId, summaryOutputFile.readAsBytesSync());
}

Iterable<String> _analyzerSourceArgsForModule(
    Module module, ScratchSpace scratchSpace) {
  return module.assetIds.map((id) {
    var uri = canonicalUriFor(id);
    var file = scratchSpace.fileFor(id);
    if (!uri.startsWith('package:')) {
      uri = file.uri.toString();
    }
    return '$uri|${file.path}';
  });
}
