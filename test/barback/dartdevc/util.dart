// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:barback/barback.dart';
import 'package:test/test.dart';

import 'package:pub/src/barback/dartdevc/module.dart';
import 'package:pub/src/barback/dartdevc/module_reader.dart';

// Keep incrementing ids so we don't accidentally create duplicates.
int _next = 0;

/// Makes a bunch of [Asset]s by parsing the keys of [assets] as an [AssetId]
/// and the values as the contents.
///
/// Returns a [Map<AssetId, Asset>] of the created [Asset]s.
Map<AssetId, Asset> makeAssets(Map<String, String> assetDescriptors) {
  var assets = <AssetId, Asset>{};
  assetDescriptors.forEach((serializedId, content) {
    var id = new AssetId.parse(serializedId);
    assets[id] = new Asset.fromString(id, content);
  });
  return assets;
}

AssetId makeAssetId({String package, String topLevelDir}) {
  _next++;
  package ??= 'pkg_$_next';
  topLevelDir ??= 'lib';
  return new AssetId(package, '$topLevelDir/$_next.dart');
}

Set<AssetId> makeAssetIds({String package, String topLevelDir}) =>
    new Set<AssetId>.from(new List.generate(
        10, (_) => makeAssetId(package: package, topLevelDir: topLevelDir)));

ModuleId makeModuleId({String package}) {
  _next++;
  package ??= 'pkg_$_next';
  return new ModuleId(package, 'name_$_next');
}

Set<ModuleId> makeModuleIds({String package}) => new Set<ModuleId>.from(
    new List.generate(10, (_) => makeModuleId(package: package)));

Module makeModule(
    {String package, Set<AssetId> directDependencies, String topLevelDir}) {
  var id = makeModuleId(package: package);
  var assetIds = makeAssetIds(package: id.package, topLevelDir: topLevelDir);
  directDependencies ??= new Set<AssetId>();
  return new Module(id, assetIds, directDependencies);
}

List<Module> makeModules({String package}) =>
    new List.generate(10, (_) => makeModule(package: package));

Matcher equalsModule(Module expected) => new _EqualsModule(expected);

class _EqualsModule extends Matcher {
  Module _expected;

  _EqualsModule(this._expected);

  bool matches(item, _) =>
      item is Module &&
      item.id == _expected.id &&
      unorderedEquals(_expected.assetIds).matches(item.assetIds, _) &&
      unorderedEquals(_expected.directDependencies)
          .matches(item.directDependencies, _);

  Description describe(Description description) =>
      description.addDescriptionOf(_expected);
}

/// Manages an in memory view of a set of module configs, mimics on disk module
/// config files.
class InMemoryModuleConfigManager {
  final _moduleConfigs = <AssetId, String>{};

  /// Adds a module config file containing serialized [modules] to
  /// [_moduleConfigs].
  ///
  /// Returns the [AssetId] for the config that was created.
  AssetId addConfig(Iterable<Module> modules, {AssetId configId}) {
    var package = modules.first.id.package;
    assert(modules.every((m) => m.id.package == package));
    configId ??= new AssetId(package, 'lib/$moduleConfigName');
    _moduleConfigs[configId] = JSON.encode(modules);
    return configId;
  }

  String readAsString(AssetId id) => _moduleConfigs[id];
}
