// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:barback/barback.dart';
import 'package:test/test.dart';

import 'package:pub/src/barback/dartdevc/module.dart';

// Keep incrementing ids so we don't accidentally create duplicates.
int _next = 0;

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

void expectModulesEqual(Module expected, Module actual) {
  expect(expected.id, equals(actual.id));
  expect(expected.assetIds, equals(actual.assetIds));
  expect(expected.directDependencies, equals(actual.directDependencies));
}
