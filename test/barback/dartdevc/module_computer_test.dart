// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/barback/dartdevc/module_computer.dart';

import 'util.dart';

main() {
  group('computeModules', () {
    group('ModuleMode.public', () {
      test('no strongly connected components, one shared lib', () async {
        var assets = makeAssets({
          'myapp|lib/a.dart': '''
            import 'b.dart';
            import 'src/c.dart';
          ''',
          'myapp|lib/b.dart': '''
            import 'src/c.dart';
          ''',
          'myapp|lib/src/c.dart': '''
            import 'd.dart';
          ''',
          'myapp|lib/src/d.dart': '',
        });

        var expectedModules = [
          equalsModule(makeModule(package: 'myapp', name: 'lib__a', srcs: [
            'myapp|lib/a.dart'
          ], directDependencies: [
            'myapp|lib/b.dart',
            'myapp|lib/src/c.dart'
          ])),
          equalsModule(makeModule(
              package: 'myapp',
              name: 'lib__b',
              srcs: ['myapp|lib/b.dart'],
              directDependencies: ['myapp|lib/src/c.dart'])),
          equalsModule(makeModule(
              package: 'myapp',
              name: 'lib__a\$lib__b',
              srcs: ['myapp|lib/src/c.dart', 'myapp|lib/src/d.dart'])),
        ];

        var modules = await computeModules(ModuleMode.public, assets.values);

        expect(modules, unorderedMatches(expectedModules));
      });

      test('single strongly connected component', () async {
        var assets = makeAssets({
          'myapp|lib/a.dart': '''
            import 'b.dart';
            import 'src/c.dart';
          ''',
          'myapp|lib/b.dart': '''
            import 'src/c.dart';
          ''',
          'myapp|lib/src/c.dart': '''
            import 'package:myapp/a.dart';
          ''',
        });

        var expectedModules = [
          equalsModule(makeModule(package: 'myapp', name: 'lib__a', srcs: [
            'myapp|lib/a.dart',
            'myapp|lib/b.dart',
            'myapp|lib/src/c.dart'
          ])),
        ];

        var modules = await computeModules(ModuleMode.public, assets.values);
        expect(modules, unorderedMatches(expectedModules));
      });

      test('multiple strongly connected components', () async {
        var assets = makeAssets({
          'myapp|lib/a.dart': '''
            import 'src/c.dart';
            import 'src/e.dart';
          ''',
          'myapp|lib/b.dart': '''
            import 'src/c.dart';
            import 'src/d.dart';
            import 'src/e.dart';
          ''',
          'myapp|lib/src/c.dart': '''
            import 'package:myapp/a.dart';
            import 'g.dart';
          ''',
          'myapp|lib/src/d.dart': '''
            import 'e.dart';
            import 'g.dart';
          ''',
          'myapp|lib/src/e.dart': '''
            import 'f.dart';
          ''',
          'myapp|lib/src/f.dart': '''
            import 'e.dart';
          ''',
          'myapp|lib/src/g.dart': '',
        });

        var expectedModules = [
          equalsModule(makeModule(package: 'myapp', name: 'lib__a', srcs: [
            'myapp|lib/a.dart',
            'myapp|lib/src/c.dart'
          ], directDependencies: [
            'myapp|lib/src/e.dart',
            'myapp|lib/src/g.dart'
          ])),
          equalsModule(makeModule(package: 'myapp', name: 'lib__b', srcs: [
            'myapp|lib/b.dart',
            'myapp|lib/src/d.dart'
          ], directDependencies: [
            'myapp|lib/src/c.dart',
            'myapp|lib/src/e.dart',
            'myapp|lib/src/g.dart'
          ])),
          equalsModule(makeModule(
              package: 'myapp',
              name: 'lib__a\$lib__b',
              srcs: [
                'myapp|lib/src/e.dart',
                'myapp|lib/src/f.dart',
                'myapp|lib/src/g.dart'
              ])),
        ];

        var modules = await computeModules(ModuleMode.public, assets.values);

        expect(modules, unorderedMatches(expectedModules));
      });

      test('ignores non-reachable assets in lib/src/ and external assets',
          () async {
        var assets = makeAssets({
          'myapp|lib/a.dart': '''
            import 'package:b/b.dart';
          ''',
          // Not imported by any public entry point, should be ignored.
          'myapp|lib/src/c.dart': '''
          ''',
        });

        var expectedModules = [
          equalsModule(makeModule(
              package: 'myapp',
              name: 'lib__a',
              srcs: ['myapp|lib/a.dart'],
              directDependencies: ['b|lib/b.dart'])),
        ];

        var modules = await computeModules(ModuleMode.public, assets.values);

        expect(modules, unorderedMatches(expectedModules));
      });

      test(
          'components can be merged into entrypoints, but other entrypoints are '
          'left alone', () async {
        var assets = makeAssets({
          'myapp|lib/a.dart': '''
            import 'b.dart';
            import 'src/c.dart';
          ''',
          'myapp|lib/b.dart': '',
          'myapp|lib/src/c.dart': '''
            import 'd.dart';
          ''',
          'myapp|lib/src/d.dart': '',
        });

        var expectedModules = [
          equalsModule(makeModule(package: 'myapp', name: 'lib__a', srcs: [
            'myapp|lib/a.dart',
            'myapp|lib/src/c.dart',
            'myapp|lib/src/d.dart'
          ], directDependencies: [
            'myapp|lib/b.dart'
          ])),
          equalsModule(makeModule(
              package: 'myapp', name: 'lib__b', srcs: ['myapp|lib/b.dart'])),
        ];

        var modules = await computeModules(ModuleMode.public, assets.values);

        expect(modules, unorderedMatches(expectedModules));
      });

      test('multiple shared libs', () async {
        var assets = makeAssets({
          'myapp|lib/a.dart': '''
            import 'src/d.dart';
            import 'src/e.dart';
            import 'src/f.dart';
          ''',
          'myapp|lib/b.dart': '''
            import 'src/d.dart';
            import 'src/e.dart';
          ''',
          'myapp|lib/c.dart': '''
            import 'src/d.dart';
            import 'src/f.dart';
          ''',
          'myapp|lib/src/d.dart': '''
          ''',
          'myapp|lib/src/e.dart': '''
            import 'd.dart';
          ''',
          'myapp|lib/src/f.dart': '''
            import 'd.dart';
          ''',
        });

        var expectedModules = [
          equalsModule(makeModule(package: 'myapp', name: 'lib__a', srcs: [
            'myapp|lib/a.dart'
          ], directDependencies: [
            'myapp|lib/src/d.dart',
            'myapp|lib/src/e.dart',
            'myapp|lib/src/f.dart'
          ])),
          equalsModule(makeModule(package: 'myapp', name: 'lib__b', srcs: [
            'myapp|lib/b.dart'
          ], directDependencies: [
            'myapp|lib/src/d.dart',
            'myapp|lib/src/e.dart',
          ])),
          equalsModule(makeModule(package: 'myapp', name: 'lib__c', srcs: [
            'myapp|lib/c.dart'
          ], directDependencies: [
            'myapp|lib/src/d.dart',
            'myapp|lib/src/f.dart'
          ])),
          equalsModule(makeModule(
              package: 'myapp',
              name: 'lib__a\$lib__b',
              srcs: ['myapp|lib/src/e.dart'],
              directDependencies: ['myapp|lib/src/d.dart'])),
          equalsModule(makeModule(
              package: 'myapp',
              name: 'lib__a\$lib__c',
              srcs: ['myapp|lib/src/f.dart'],
              directDependencies: ['myapp|lib/src/d.dart'])),
          equalsModule(makeModule(
              package: 'myapp',
              name: 'lib__a\$lib__b\$lib__c',
              srcs: ['myapp|lib/src/d.dart'])),
        ];

        var modules = await computeModules(ModuleMode.public, assets.values);

        expect(modules, unorderedMatches(expectedModules));
      });

      test('part files are merged into the parent libraries component',
          () async {
        var assets = makeAssets({
          'myapp|lib/a.dart': '''
            library a;

            part 'a.part.dart';
            part 'src/a.part.dart';
          ''',
          'myapp|lib/a.part.dart': '''
            part of a;
          ''',
          'myapp|lib/src/a.part.dart': '''
            part of a;
          ''',
        });

        var expectedModules = [
          equalsModule(makeModule(package: 'myapp', name: 'lib__a', srcs: [
            'myapp|lib/a.dart',
            'myapp|lib/a.part.dart',
            'myapp|lib/src/a.part.dart'
          ])),
        ];

        var modules = await computeModules(ModuleMode.public, assets.values);

        expect(modules, unorderedMatches(expectedModules));
      });

      test('throws if given non-lib srcs', () async {
        var assets = makeAssets({
          'myapp|web/a.dart': '',
        });
        expect(computeModules(ModuleMode.public, assets.values),
            throwsArgumentError);
      });
    });

    group("ModuleMode.private", () {
      test('shared lib, only files with a `main` are entry points', () async {
        var assets = makeAssets({
          'myapp|web/a.dart': '''
            import 'b.dart';
            import 'c.dart';

            void main() {}
          ''',
          'myapp|web/b.dart': '''
            import 'c.dart';

            void main() {}
          ''',
          'myapp|web/c.dart': '''
            import 'd.dart';
          ''',
          'myapp|web/d.dart': '',
        });

        var expectedModules = [
          equalsModule(makeModule(
              package: 'myapp',
              name: 'web__a',
              srcs: ['myapp|web/a.dart'],
              directDependencies: ['myapp|web/b.dart', 'myapp|web/c.dart'])),
          equalsModule(makeModule(
              package: 'myapp',
              name: 'web__b',
              srcs: ['myapp|web/b.dart'],
              directDependencies: ['myapp|web/c.dart'])),
          equalsModule(makeModule(
              package: 'myapp',
              name: 'web__a\$web__b',
              srcs: ['myapp|web/c.dart', 'myapp|web/d.dart'])),
        ];

        var modules = await computeModules(ModuleMode.private, assets.values);

        expect(modules, unorderedMatches(expectedModules));
      });

      test('strongly connected component under web', () async {
        var assets = makeAssets({
          'myapp|web/a.dart': '''
            import 'b.dart';

            void main() {}
          ''',
          'myapp|web/b.dart': '''
            import 'a.dart';
            import 'c.dart';

            void main() {}
          ''',
          'myapp|web/c.dart': '''
            import 'd.dart';
          ''',
          'myapp|web/d.dart': '''
            import 'c.dart';
          ''',
          'myapp|web/e.dart': '''
            import 'd.dart';

            void main() {}
          ''',
        });

        var expectedModules = [
          equalsModule(makeModule(
              package: 'myapp',
              name: 'web__a',
              srcs: ['myapp|web/a.dart', 'myapp|web/b.dart'],
              directDependencies: ['myapp|web/c.dart'])),
          equalsModule(makeModule(
              package: 'myapp',
              name: 'web__e',
              srcs: ['myapp|web/e.dart'],
              directDependencies: ['myapp|web/d.dart'])),
          equalsModule(makeModule(
              package: 'myapp',
              name: 'web__a\$web__e',
              srcs: ['myapp|web/c.dart', 'myapp|web/d.dart'])),
        ];

        var modules = await computeModules(ModuleMode.private, assets.values);

        expect(modules, unorderedMatches(expectedModules));
      });

      test('throws if given lib srcs', () async {
        var assets = makeAssets({
          'myapp|lib/a.dart': '',
        });
        expect(computeModules(ModuleMode.private, assets.values),
            throwsArgumentError);
      });

      test('throws if given srcs in different top level dirs', () async {
        var assets = makeAssets({
          'myapp|web/a.dart': '',
          'myapp|example/b.dart': '',
        });
        expect(computeModules(ModuleMode.private, assets.values),
            throwsArgumentError);
      });
    });
  });
}
