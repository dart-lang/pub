// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:barback/barback.dart';

import 'module.dart';
import 'module_reader.dart';
import 'scratch_space.dart';
import 'summaries.dart';

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
      scratchSpace =
          await ScratchSpace.create(allAssetIds, transform.readInput);
      await Future.wait(modules.map((m) async {
        var outputs = createUnlinkedSummaryForModule(
            m, scratchSpace, transform.logger.error);
        await Future.wait(outputs.values.map(
            (futureAsset) async => transform.addOutput(await futureAsset)));
      }));
    } finally {
      scratchSpace?.delete();
    }
  }
}
