// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:barback/barback.dart';
import 'package:test/test.dart';

import 'package:pub/src/barback/dartdevc/module_computer.dart';

import 'util.dart';

main() {
  group('computeModules', () {
    test('no strongly connected components, one shared lib', () async {
      var assets = makeAssets({
        'a|lib/a.dart': '''
          import 'b.dart';
          import 'src/c.dart';
        ''',
        'a|lib/b.dart': '''
          import 'src/c.dart';
        ''',
        'a|lib/src/c.dart': '''
          import 'd.dart';
        ''',
        'a|lib/src/d.dart': '''
        ''',
      });

      var expectedModules = [
        equalsModule(makeModule(
            package: 'a',
            name: 'lib__a',
            srcs: ['a|lib/a.dart'],
            directDependencies: ['a|lib/b.dart', 'a|lib/src/c.dart'])),
        equalsModule(makeModule(
            package: 'a',
            name: 'lib__b',
            srcs: ['a|lib/b.dart'],
            directDependencies: ['a|lib/src/c.dart'])),
        equalsModule(makeModule(
            package: 'a',
            name: 'lib__a\$lib__b',
            srcs: ['a|lib/src/c.dart', 'a|lib/src/d.dart'],
            directDependencies: <AssetId>[])),
      ];

      var modules = await computeModules(ModuleMode.public, assets.values);

      expect(modules, unorderedMatches(expectedModules));
    });

    test('single strongly connected component', () async {
      var assets = makeAssets({
        'a|lib/a.dart': '''
            import 'b.dart';
            import 'src/c.dart';
          ''',
        'a|lib/b.dart': '''
            import 'src/c.dart';
          ''',
        'a|lib/src/c.dart': '''
            import 'package:a/a.dart';
          ''',
      });

      var expectedModules = [
        equalsModule(makeModule(
            package: 'a',
            name: 'lib__a',
            srcs: ['a|lib/a.dart', 'a|lib/b.dart', 'a|lib/src/c.dart'])),
      ];

      var modules = await computeModules(ModuleMode.public, assets.values);
      expect(modules, unorderedMatches(expectedModules));
    });

    test('multiple strongly connected components', () async {
      var assets = makeAssets({
        'a|lib/a.dart': '''
            import 'src/c.dart';
            import 'src/e.dart';
          ''',
        'a|lib/b.dart': '''
            import 'src/c.dart';
            import 'src/d.dart';
            import 'src/e.dart';
          ''',
        'a|lib/src/c.dart': '''
            import 'package:a/a.dart';
            import 'g.dart';
          ''',
        'a|lib/src/d.dart': '''
            import 'e.dart';
            import 'g.dart';
          ''',
        'a|lib/src/e.dart': '''
            import 'f.dart';
          ''',
        'a|lib/src/f.dart': '''
            import 'e.dart';
          ''',
        'a|lib/src/g.dart': '''
          ''',
      });

      var expectedModules = [
        equalsModule(makeModule(
            package: 'a',
            name: 'lib__a',
            srcs: ['a|lib/a.dart', 'a|lib/src/c.dart'],
            directDependencies: ['a|lib/src/e.dart', 'a|lib/src/g.dart'])),
        equalsModule(makeModule(package: 'a', name: 'lib__b', srcs: [
          'a|lib/b.dart',
          'a|lib/src/d.dart'
        ], directDependencies: [
          'a|lib/src/c.dart',
          'a|lib/src/e.dart',
          'a|lib/src/g.dart'
        ])),
        equalsModule(makeModule(package: 'a', name: 'lib__a\$lib__b', srcs: [
          'a|lib/src/e.dart',
          'a|lib/src/f.dart',
          'a|lib/src/g.dart'
        ])),
      ];

      var modules = await computeModules(ModuleMode.public, assets.values);

      expect(modules, unorderedMatches(expectedModules));
    });

    test('ignores non-reachable assets in lib/src/ and external assets',
        () async {
      var assets = makeAssets({
        'a|lib/a.dart': '''
            import 'package:b/b.dart';
          ''',
        // Not imported by any public entry point, should be ignored.
        'a|lib/src/c.dart': '''
          ''',
      });

      var expectedModules = [
        equalsModule(makeModule(
            package: 'a',
            name: 'lib__a',
            srcs: ['a|lib/a.dart'],
            directDependencies: ['b|lib/b.dart'])),
      ];

      var modules = await computeModules(ModuleMode.public, assets.values);

      expect(modules, unorderedMatches(expectedModules));
    });

    test(
        'components can be merged into entrypoints, but other entrypoints are '
        'left alone', () async {
      var assets = makeAssets({
        'a|lib/a.dart': '''
          import 'b.dart';
          import 'src/c.dart';
        ''',
        'a|lib/b.dart': '''
        ''',
        'a|lib/src/c.dart': '''
          import 'd.dart';
        ''',
        'a|lib/src/d.dart': '''
        ''',
      });

      var expectedModules = [
        equalsModule(makeModule(
            package: 'a',
            name: 'lib__a',
            srcs: ['a|lib/a.dart', 'a|lib/src/c.dart', 'a|lib/src/d.dart'],
            directDependencies: ['a|lib/b.dart'])),
        equalsModule(
            makeModule(package: 'a', name: 'lib__b', srcs: ['a|lib/b.dart'])),
      ];

      var modules = await computeModules(ModuleMode.public, assets.values);

      expect(modules, unorderedMatches(expectedModules));
    });

    test('multiple shared libs', () async {
      var assets = makeAssets({
        'a|lib/a.dart': '''
            import 'src/d.dart';
            import 'src/e.dart';
            import 'src/f.dart';
          ''',
        'a|lib/b.dart': '''
            import 'src/d.dart';
            import 'src/e.dart';
          ''',
        'a|lib/c.dart': '''
            import 'src/d.dart';
            import 'src/f.dart';
          ''',
        'a|lib/src/d.dart': '''
          ''',
        'a|lib/src/e.dart': '''
            import 'd.dart';
          ''',
        'a|lib/src/f.dart': '''
            import 'd.dart';
          ''',
      });

      var expectedModules = [
        equalsModule(makeModule(package: 'a', name: 'lib__a', srcs: [
          'a|lib/a.dart'
        ], directDependencies: [
          'a|lib/src/d.dart',
          'a|lib/src/e.dart',
          'a|lib/src/f.dart'
        ])),
        equalsModule(makeModule(package: 'a', name: 'lib__b', srcs: [
          'a|lib/b.dart'
        ], directDependencies: [
          'a|lib/src/d.dart',
          'a|lib/src/e.dart',
        ])),
        equalsModule(makeModule(
            package: 'a',
            name: 'lib__c',
            srcs: ['a|lib/c.dart'],
            directDependencies: ['a|lib/src/d.dart', 'a|lib/src/f.dart'])),
        equalsModule(makeModule(
            package: 'a',
            name: 'lib__a\$lib__b',
            srcs: ['a|lib/src/e.dart'],
            directDependencies: ['a|lib/src/d.dart'])),
        equalsModule(makeModule(
            package: 'a',
            name: 'lib__a\$lib__c',
            srcs: ['a|lib/src/f.dart'],
            directDependencies: ['a|lib/src/d.dart'])),
        equalsModule(makeModule(
            package: 'a',
            name: 'lib__a\$lib__b\$lib__c',
            srcs: ['a|lib/src/d.dart'])),
      ];

      var modules = await computeModules(ModuleMode.public, assets.values);

      expect(modules, unorderedMatches(expectedModules));
    });
  });
}
