// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:barback/barback.dart';
import 'package:path/path.dart' as p;

import 'module.dart';

typedef FutureOr<String> ReadAsString(AssetId id);

/// The name of the module config files.
const moduleConfigName = '.moduleConfig';

/// Reads and caches [Module]s, and allows you to get transitive dependencies.
class ModuleReader {
  final ReadAsString assetReader;

  final _modulesByAssetId = <AssetId, Module>{};

  final _modulesByModuleId = <ModuleId, Module>{};

  final _moduleConfigFutures = <AssetId, Future<List<Module>>>{};

  ModuleReader(this.assetReader);

  /// Returns a [Future<Module>] containing [id].
  ///
  /// Module configs are expected to live under the same top level directory of
  /// the package as [id].
  Future<Module> moduleFor(AssetId id) async {
    var parts = p.split(p.dirname(id.path));
    if (parts.length == 0) {
      throw new ArgumentError("Unexpected asset `$id` which isn't under a top "
          "level directory of its package.");
    }
    var moduleConfigId =
        new AssetId(id.package, p.join(parts.first, moduleConfigName));
    await readModules(moduleConfigId);
    return _modulesByAssetId[id];
  }

  /// Computes the transitive deps of [id] by reading all the modules for all
  /// its dependencies recursively.
  ///
  /// Assumes that any dependencies modules are either already loaded or exist
  /// in the default module config file for their package.
  Future<Set<ModuleId>> readTransitiveDeps(Module module) async {
    var allModuleDepIds = new Set<ModuleId>();
    Future updateDeps(Iterable<AssetId> assetDepIds) async {
      for (var assetDepId in assetDepIds) {
        var assetDepModule = await moduleFor(assetDepId);
        if (!allModuleDepIds.add(assetDepModule.id)) continue;
        await updateDeps(assetDepModule.directDependencies);
      }
    }

    await updateDeps(module.directDependencies);
    return allModuleDepIds;
  }

  /// Loads all [Module]s in [moduleConfigId] if they are not already loaded.
  ///
  /// Populates [_modules] and [_modulesByAssetId] for each loaded [Module].
  ///
  /// Returns a [Future<List<Module>>] representing all modules contained in
  /// [moduleConfigId].
  Future<List<Module>> readModules(AssetId moduleConfigId) {
    return _moduleConfigFutures.putIfAbsent(moduleConfigId, () async {
      var modules = <Module>[];
      var content = await assetReader(moduleConfigId);
      var serializedModules = JSON.decode(content) as List<List<List<dynamic>>>;
      for (var serializedModule in serializedModules) {
        var module = new Module.fromJson(serializedModule);
        modules.add(module);
        _modulesByModuleId[module.id] = module;
        for (var id in module.assetIds) {
          if (_modulesByAssetId.containsKey(id)) {
            throw new StateError('Assets can only exist in one module, but $id'
                'was found in both ${_modulesByAssetId[id].id} and '
                '${module.id}');
          }
          _modulesByAssetId[id] = module;
        }
      }
      return modules;
    });
  }
}
