// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:barback/barback.dart';
import 'package:test/test.dart';

import 'package:pub/src/dartdevc/module.dart';
import 'package:pub/src/dartdevc/module_reader.dart';

import 'util.dart';

void main() {
  InMemoryModuleConfigManager configManager;
  ModuleReader moduleReader;

  setUp(() {
    configManager = new InMemoryModuleConfigManager();
    moduleReader = new ModuleReader(configManager.readAsString);
  });

  group('ModuleReader', () {
    group('single config with single module and no deps', () {
      Module originalModule;
      AssetId originalModuleConfig;
      setUp(() {
        originalModule = makeModule();
        originalModuleConfig = configManager.addConfig([originalModule]);
      });

      test('readModules', () async {
        var modules = await moduleReader.readModules(originalModuleConfig);
        expect(modules.length, 1);
        expect(modules.first, equalsModule(originalModule));
      });

      test('moduleFor', () async {
        for (var assetId in originalModule.assetIds) {
          var module = await moduleReader.moduleFor(assetId);
          expect(module, equalsModule(originalModule));
        }
      });

      test('transitiveDependencies', () async {
        var modules = await moduleReader.readModules(originalModuleConfig);
        var deps = await moduleReader.readTransitiveDeps(modules.first);
        expect(deps, isEmpty);
      });

      test('invalidatePackage', () async {
        var originalModules =
            await moduleReader.readModules(originalModuleConfig);
        moduleReader.invalidatePackage(originalModuleConfig.package);
        var newModule = makeModule(package: originalModuleConfig.package);
        var newModuleConfig = configManager.addConfig([newModule]);
        expect(newModuleConfig, equals(originalModuleConfig));
        var newModules = await moduleReader.readModules(originalModuleConfig);
        expect(originalModules.map((module) => module.id),
            isNot(unorderedEquals(newModules.map((module) => module.id))));
      });
    });

    group('multiple configs with transitive deps', () {
      var packageAModuleA = makeModule(package: 'a');
      var packageAModuleB = makeModule(package: 'a')
        ..directDependencies.add(packageAModuleA.assetIds.first);
      var packageAModuleC = makeModule(package: 'a')
        ..directDependencies.add(packageAModuleA.assetIds.last);
      var packageAModules = [
        packageAModuleA,
        packageAModuleB,
        packageAModuleC,
      ];

      var packageBModuleA = makeModule(package: 'b')
        ..directDependencies.add(packageAModuleB.assetIds.last);
      var packageBModuleB = makeModule(package: 'b')
        ..directDependencies.add(packageBModuleA.assetIds.first);
      var packageBModules = [
        packageBModuleA,
        packageBModuleB,
      ];
      var packageCLibModule = makeModule(package: 'c')
        ..directDependencies.add(packageBModuleB.assetIds.last);
      var packageCModules = [packageCLibModule];
      var packageCWebModule = makeModule(package: 'c', topLevelDir: 'web')
        ..directDependencies.add(packageCLibModule.assetIds.first);
      var packageCWebModules = [packageCWebModule];

      var libModules = [
        packageAModuleA,
        packageAModuleB,
        packageAModuleC,
        packageBModuleA,
        packageBModuleB,
        packageCLibModule,
      ];

      AssetId packageAModuleConfig;
      AssetId packageBModuleConfig;
      AssetId packageCModuleConfig;
      AssetId packageCWebModuleConfig;

      setUp(() {
        packageAModuleConfig = configManager.addConfig(packageAModules);
        packageBModuleConfig = configManager.addConfig([
          packageBModuleA,
          packageBModuleB,
        ]);
        packageCModuleConfig = configManager.addConfig([packageCLibModule]);
        packageCWebModuleConfig = configManager.addConfig([packageCWebModule],
            configId: new AssetId('c', 'web/$moduleConfigName'));
      });

      test('readModules', () async {
        var expectedModules = {
          packageAModuleConfig: packageAModules,
          packageBModuleConfig: packageBModules,
          packageCModuleConfig: packageCModules,
          packageCWebModuleConfig: packageCWebModules,
        };
        for (var config in expectedModules.keys) {
          var modules = await moduleReader.readModules(config);
          for (int i = 0; i < modules.length; i++) {
            expect(modules[i], equalsModule(expectedModules[config][i]));
          }
        }
      });

      test('moduleFor', () async {
        var allModules = [packageCWebModule]..addAll(libModules);
        for (var expected in allModules) {
          for (var assetId in expected.assetIds) {
            var actual = await moduleReader.moduleFor(assetId);
            expect(expected, equalsModule(actual));
          }
        }
      });

      test('transitiveDependencies', () async {
        expect(await moduleReader.readTransitiveDeps(packageAModuleA), isEmpty);
        expect(await moduleReader.readTransitiveDeps(packageAModuleB),
            unorderedEquals([packageAModuleA.id]));
        expect(await moduleReader.readTransitiveDeps(packageAModuleC),
            unorderedEquals([packageAModuleA.id]));

        expect(await moduleReader.readTransitiveDeps(packageBModuleA),
            unorderedEquals([packageAModuleA.id, packageAModuleB.id]));
        expect(
            await moduleReader.readTransitiveDeps(packageBModuleB),
            unorderedEquals(
                [packageAModuleA.id, packageAModuleB.id, packageBModuleA.id]));

        expect(
            await moduleReader.readTransitiveDeps(packageCLibModule),
            unorderedEquals([
              packageAModuleA.id,
              packageAModuleB.id,
              packageBModuleA.id,
              packageBModuleB.id,
            ]));
        expect(
            await moduleReader.readTransitiveDeps(packageCWebModule),
            unorderedEquals([
              packageAModuleA.id,
              packageAModuleB.id,
              packageBModuleA.id,
              packageBModuleB.id,
              packageCLibModule.id,
            ]));
      });

      test('invalidatePackage', () async {
        var modules = await moduleReader.readModules(packageAModuleConfig);
        expect(
            modules
                .firstWhere((module) => module.id == packageAModuleC.id)
                .directDependencies,
            isNot(contains(packageAModuleB.assetIds.first)));

        packageAModuleC.directDependencies.add(packageAModuleB.assetIds.first);
        packageAModuleConfig = configManager.addConfig(packageAModules);
        moduleReader.invalidatePackage(packageAModuleC.id.package);

        modules = await moduleReader.readModules(packageAModuleConfig);
        expect(
            modules
                .firstWhere((module) => module.id == packageAModuleC.id)
                .directDependencies,
            contains(packageAModuleB.assetIds.first));
      });
    });
  });
}
