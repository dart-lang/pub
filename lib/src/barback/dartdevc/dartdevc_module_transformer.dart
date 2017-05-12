// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:barback/barback.dart';

import 'dartdevc.dart';
import 'module.dart';
import 'module_reader.dart';
import 'scratch_space.dart';

/// Creates dartdevc modules given [moduleConfigName] files which describe a set
/// of [Module]s.
///
/// Linked summaries should have already been created for all modules and will
/// be read in to create the modules.
class DartDevcModuleTransformer extends Transformer {
  @override
  String get allowedExtensions => moduleConfigName;

  final Map<String, String> environmentConstants;
  final BarbackMode mode;

  DartDevcModuleTransformer(this.mode, {this.environmentConstants = const {}});

  @override
  Future apply(Transform transform) async {
    ScratchSpace scratchSpace;
    var reader = new ModuleReader(transform.readInputAsString);
    var modules = await reader.readModules(transform.primaryInput.id);
    try {
      var allAssetIds = new Set<AssetId>();
      var summariesForModule = <ModuleId, Set<AssetId>>{};
      for (var module in modules) {
        var transitiveModuleDeps = await reader.readTransitiveDeps(module);
        var linkedSummaryIds =
            transitiveModuleDeps.map((depId) => depId.linkedSummaryId).toSet();
        summariesForModule[module.id] = linkedSummaryIds;
        allAssetIds..addAll(module.assetIds)..addAll(linkedSummaryIds);
      }
      // Create a single temp environment for all the modules in this package.
      scratchSpace =
          await ScratchSpace.create(allAssetIds, transform.readInput);
      // We only log warnings in debug mode for ddc modules because they don't all
      // need to compile successfully, only the ones imported by an entrypoint do.
      var logError = mode == BarbackMode.DEBUG
          ? transform.logger.warning
          : transform.logger.error;
      await Future.wait(modules.map((m) async {
        var outputs = createDartdevcModule(m, scratchSpace,
            summariesForModule[m.id], environmentConstants, mode, logError);
        await Future.wait(outputs.values.map(
            (futureAsset) async => transform.addOutput(await futureAsset)));
      }));
    } finally {
      scratchSpace?.delete();
    }
  }
}
