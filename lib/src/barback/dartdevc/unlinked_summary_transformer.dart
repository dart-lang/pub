// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:barback/barback.dart';
import 'package:bazel_worker/bazel_worker.dart';

import 'workers.dart';
import 'module.dart';
import 'module_reader.dart';
import 'scratch_space.dart';

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
    ScratchSpace scratchSpace;
    try {
      var allAssetIds = modules.fold(new Set<AssetId>(), (allAssets, module) {
        allAssets.addAll(module.assetIds);
        return allAssets;
      });
      // Create a single temp environment for all the modules in this package.
      scratchSpace = await ScratchSpace.create(allAssetIds, transform.readInput);
      await Future.wait(modules
          .map((m) => _createUnlinkedSummaryForModule(m, scratchSpace, transform)));
    } finally {
      scratchSpace?.delete();
    }
  }
}

Future _createUnlinkedSummaryForModule(
    Module module, ScratchSpace scratchSpace, Transform transform) async {
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
    transform.logger
        .error('Error creating unlinked summaries for module: ${module.id}.\n'
            '${response.output}');
  } else {
    transform.addOutput(new Asset.fromBytes(
        module.id.unlinkedSummaryId, summaryOutputFile.readAsBytesSync()));
  }
}
