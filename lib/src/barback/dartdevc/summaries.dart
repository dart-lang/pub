// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:barback/barback.dart';
import 'package:bazel_worker/bazel_worker.dart';

import 'module.dart';
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
Map<AssetId, Future<Asset>> createLinkedSummaryForModule(
    Module module,
    Set<AssetId> unlinkedSummaryIds,
    ScratchSpace scratchSpace,
    logError(String message)) {
  var outputCompleters = <AssetId, Completer<Asset>>{
    module.id.linkedSummaryId: new Completer<Asset>(),
  };

  () async {
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
      var message =
          'Error creating linked summaries for module: ${module.id}.\n'
          '${response.output}';
      logError(message);
      outputCompleters.values.forEach((completer) {
        completer.completeError(message);
      });
    } else {
      outputCompleters[module.id.linkedSummaryId].complete(new Asset.fromBytes(
          module.id.linkedSummaryId, summaryOutputFile.readAsBytesSync()));
    }
  }();

  var outputFutures = <AssetId, Future<Asset>>{};
  outputCompleters.forEach((k, v) => outputFutures[k] = v.future);
  return outputFutures;
}

/// Creates an unlinked summary for [module].
///
/// [scratchSpace] must have the Dart sources for this module available.
///
/// Synchronously returns a `Map<AssetId, Future<Asset>>` so that you can know
/// immediately what assets will be output.
Map<AssetId, Future<Asset>> createUnlinkedSummaryForModule(
    Module module, ScratchSpace scratchSpace, logError(String message)) {
  var outputCompleters = <AssetId, Completer<Asset>>{
    module.id.unlinkedSummaryId: new Completer<Asset>(),
  };

  () async {
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
    request.arguments.addAll(module.assetIds.map((id) {
      var uri = canonicalUriFor(id);
      if (!uri.startsWith('package:')) {
        uri = 'file://$uri';
      }
      return '$uri|${scratchSpace.fileFor(id).path}';
    }));
    var response = await analyzerDriver.doWork(request);
    if (response.exitCode == EXIT_CODE_ERROR) {
      var message =
          'Error creating unlinked summaries for module: ${module.id}.\n'
          '${response.output}';
      logError(message);
      outputCompleters.values.forEach((completer) {
        completer.completeError(message);
      });
    } else {
      outputCompleters[module.id.unlinkedSummaryId].complete(
          new Asset.fromBytes(module.id.unlinkedSummaryId,
              summaryOutputFile.readAsBytesSync()));
    }
  }();

  var outputFutures = <AssetId, Future<Asset>>{};
  outputCompleters.forEach((k, v) => outputFutures[k] = v.future);
  return outputFutures;
}
