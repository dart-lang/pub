// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('URL encodes the package name', () async {
    await serveNoPackages();

    await d.appDir({}).create();

    await pubAdd(
        args: ['bad name!:1.2.3'],
        error: allOf([
          contains(
              "Because myapp depends on bad name! any which doesn't exist (could "
              'not find package bad name! at http://localhost:'),
          contains('), version solving failed.')
        ]),
        exitCode: exit_codes.DATA);

    await d.appDir({}).validate();

    await d.dir(appPath, [
      d.nothing('.dart_tool/package_config.json'),
      d.nothing('pubspec.lock'),
      d.nothing('.packages'),
    ]).validate();
  });

  group('normally', () {
    test('adds a package from a pub server', () async {
      await servePackages((builder) => builder.serve('foo', '1.2.3'));

      await d.appDir({}).create();

      await pubAdd(args: ['foo:1.2.3']);

      await d.cacheDir({'foo': '1.2.3'}).validate();
      await d.appPackagesFile({'foo': '1.2.3'}).validate();
      await d.appDir({'foo': '1.2.3'}).validate();
    });

    test('dry run does not actually add the package or modify the pubspec',
        () async {
      await servePackages((builder) => builder.serve('foo', '1.2.3'));

      await d.appDir({}).create();

      await pubAdd(
          args: ['foo:1.2.3', '--dry-run'],
          output: allOf([
            contains('Would change 1 dependency'),
            contains('+ foo 1.2.3')
          ]));

      await d.appDir({}).validate();
      await d.dir(appPath, [
        d.nothing('.dart_tool/package_config.json'),
        d.nothing('pubspec.lock'),
        d.nothing('.packages'),
      ]).validate();
    });

    test(
        'adds a package from a pub server even when dependencies key does not exist',
        () async {
      await servePackages((builder) => builder.serve('foo', '1.2.3'));

      await d.dir(appPath, [
        d.pubspec({'name': 'myapp'})
      ]).create();

      await pubAdd(args: ['foo:1.2.3']);

      await d.cacheDir({'foo': '1.2.3'}).validate();
      await d.appPackagesFile({'foo': '1.2.3'}).validate();
      await d.appDir({'foo': '1.2.3'}).validate();
    });

    group('overrides existing version constraint if package exists', () {
      test('if package is added without a version constraint', () async {
        await servePackages((builder) {
          builder.serve('foo', '1.2.3');
          builder.serve('foo', '1.2.2');
        });

        await d.appDir({'foo': '1.2.2'}).create();

        await pubAdd(args: ['foo']);

        await d.cacheDir({'foo': '1.2.3'}).validate();
        await d.appPackagesFile({'foo': '1.2.3'}).validate();
        await d.appDir({'foo': '^1.2.3'}).validate();
      });

      test('if package is added with a specific version constraint', () async {
        await servePackages((builder) {
          builder.serve('foo', '1.2.3');
          builder.serve('foo', '1.2.2');
        });

        await d.appDir({'foo': '1.2.2'}).create();

        await pubAdd(args: ['foo:1.2.3']);

        await d.cacheDir({'foo': '1.2.3'}).validate();
        await d.appPackagesFile({'foo': '1.2.3'}).validate();
        await d.appDir({'foo': '1.2.3'}).validate();
      });

      test('if package is added with a version constraint range', () async {
        await servePackages((builder) {
          builder.serve('foo', '1.2.3');
          builder.serve('foo', '1.2.2');
        });

        await d.appDir({'foo': '1.2.2'}).create();

        await pubAdd(args: ['foo:>=1.2.2']);

        await d.cacheDir({'foo': '1.2.3'}).validate();
        await d.appPackagesFile({'foo': '1.2.3'}).validate();
        await d.appDir({'foo': '>=1.2.2'}).validate();
      });
    });

    test('removes dev_dependency and add to normal dependency', () async {
      await servePackages((builder) {
        builder.serve('foo', '1.2.3');
        builder.serve('foo', '1.2.2');
      });

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependencies': {},
          'dev_dependencies': {'foo': '1.2.2'}
        })
      ]).create();

      await pubAdd(
          args: ['foo:1.2.3'],
          output: contains(
              '"foo" was found in dev_dependencies. Removing "foo" and '
              'adding it to dependencies instead.'));

      await d.cacheDir({'foo': '1.2.3'}).validate();
      await d.appPackagesFile({'foo': '1.2.3'}).validate();
      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependencies': {'foo': '1.2.3'},
          'dev_dependencies': {}
        })
      ]).validate();
    });

    group('dependency override', () {
      test('passes if package does not specify a range', () async {
        await servePackages((builder) {
          builder.serve('foo', '1.2.3');
          builder.serve('foo', '1.2.2');
        });

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dependencies': {},
            'dependency_overrides': {'foo': '1.2.2'}
          })
        ]).create();

        await pubAdd(args: ['foo']);

        await d.cacheDir({'foo': '1.2.2'}).validate();
        await d.appPackagesFile({'foo': '1.2.2'}).validate();
        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dependencies': {'foo': '^1.2.2'},
            'dependency_overrides': {'foo': '1.2.2'}
          })
        ]).validate();
      });

      test('passes if constraint matches git dependency override', () async {
        await servePackages((builder) {
          builder.serve('foo', '1.2.3');
        });

        await d.git('foo.git',
            [d.libDir('foo'), d.libPubspec('foo', '1.2.3')]).create();

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dependencies': {},
            'dependency_overrides': {
              'foo': {'git': '../foo.git'}
            }
          })
        ]).create();

        await pubAdd(args: ['foo:1.2.3']);

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dependencies': {'foo': '1.2.3'},
            'dependency_overrides': {
              'foo': {'git': '../foo.git'}
            }
          })
        ]).validate();
      });

      test('passes if constraint matches path dependency override', () async {
        await servePackages((builder) {
          builder.serve('foo', '1.2.2');
        });
        await d.dir(
            'foo', [d.libDir('foo'), d.libPubspec('foo', '1.2.2')]).create();

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dependencies': {},
            'dependency_overrides': {
              'foo': {'path': '../foo'}
            }
          })
        ]).create();

        await pubAdd(args: ['foo:1.2.2']);

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dependencies': {'foo': '1.2.2'},
            'dependency_overrides': {
              'foo': {'path': '../foo'}
            }
          })
        ]).validate();
      });

      test('fails with bad version constraint', () async {
        await servePackages((builder) {
          builder.serve('foo', '1.2.3');
        });

        await d.dir(appPath, [
          d.pubspec({'name': 'myapp', 'dependencies': {}})
        ]).create();

        await pubAdd(
            args: ['foo:one-two-three'],
            exitCode: exit_codes.USAGE,
            error: contains(
                'Could not parse version "one-two-three". Unknown text at "one-two-three"'));

        await d.dir(appPath, [
          d.pubspec({'name': 'myapp', 'dependencies': {}}),
          d.nothing('.dart_tool/package_config.json'),
          d.nothing('pubspec.lock'),
          d.nothing('.packages'),
        ]).validate();
      });

      test('fails if constraint does not match override', () async {
        await servePackages((builder) {
          builder.serve('foo', '1.2.3');
          builder.serve('foo', '1.2.2');
        });

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dependencies': {},
            'dependency_overrides': {'foo': '1.2.2'}
          })
        ]).create();

        await pubAdd(
            args: ['foo:1.2.3'],
            exitCode: exit_codes.DATA,
            error: contains(
                '"foo" resolved to "1.2.2" which does not satisfy constraint '
                '"1.2.3". This could be caused by "dependency_overrides".'));

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dependencies': {},
            'dependency_overrides': {'foo': '1.2.2'}
          }),
          d.nothing('.dart_tool/package_config.json'),
          d.nothing('pubspec.lock'),
          d.nothing('.packages'),
        ]).validate();
      });

      test('fails if constraint matches git dependency override', () async {
        await servePackages((builder) {
          builder.serve('foo', '1.2.3');
        });

        await d.git('foo.git',
            [d.libDir('foo'), d.libPubspec('foo', '1.0.0')]).create();

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dependencies': {},
            'dependency_overrides': {
              'foo': {'git': '../foo.git'}
            }
          })
        ]).create();

        await pubAdd(
            args: ['foo:1.2.3'],
            exitCode: exit_codes.DATA,
            error: contains(
                '"foo" resolved to "1.0.0" which does not satisfy constraint '
                '"1.2.3". This could be caused by "dependency_overrides".'));

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dependencies': {},
            'dependency_overrides': {
              'foo': {'git': '../foo.git'}
            }
          }),
          d.nothing('.dart_tool/package_config.json'),
          d.nothing('pubspec.lock'),
          d.nothing('.packages'),
        ]).validate();
      });

      test('fails if constraint does not match path dependency override',
          () async {
        await servePackages((builder) {
          builder.serve('foo', '1.2.2');
        });
        await d.dir(
            'foo', [d.libDir('foo'), d.libPubspec('foo', '1.0.0')]).create();

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dependencies': {},
            'dependency_overrides': {
              'foo': {'path': '../foo'}
            }
          })
        ]).create();

        await pubAdd(
            args: ['foo:1.2.2'],
            exitCode: exit_codes.DATA,
            error: contains(
                '"foo" resolved to "1.0.0" which does not satisfy constraint '
                '"1.2.2". This could be caused by "dependency_overrides".'));

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dependencies': {},
            'dependency_overrides': {
              'foo': {'path': '../foo'}
            }
          }),
          d.nothing('.dart_tool/package_config.json'),
          d.nothing('pubspec.lock'),
          d.nothing('.packages'),
        ]).validate();
      });
    });
  });

  group('--dev', () {
    test('--dev adds packages to dev_dependencies instead', () async {
      await servePackages((builder) => builder.serve('foo', '1.2.3'));

      await d.dir(appPath, [
        d.pubspec({'name': 'myapp', 'dev_dependencies': {}})
      ]).create();

      await pubAdd(args: ['--dev', 'foo:1.2.3']);

      await d.appPackagesFile({'foo': '1.2.3'}).validate();

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dev_dependencies': {'foo': '1.2.3'}
        })
      ]).validate();
    });

    group('overrides existing version constraint if package exists', () {
      test('if package is added without a version constraint', () async {
        await servePackages((builder) {
          builder.serve('foo', '1.2.3');
          builder.serve('foo', '1.2.2');
        });

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dev_dependencies': {'foo': '1.2.2'}
          })
        ]).create();

        await pubAdd(args: ['foo', '--dev']);

        await d.cacheDir({'foo': '1.2.3'}).validate();
        await d.appPackagesFile({'foo': '1.2.3'}).validate();
        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dev_dependencies': {'foo': '^1.2.3'}
          })
        ]).validate();
      });

      test('if package is added with a specific version constraint', () async {
        await servePackages((builder) {
          builder.serve('foo', '1.2.3');
          builder.serve('foo', '1.2.2');
        });

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dev_dependencies': {'foo': '1.2.2'}
          })
        ]).create();

        await pubAdd(args: ['foo:1.2.3', '--dev']);

        await d.cacheDir({'foo': '1.2.3'}).validate();
        await d.appPackagesFile({'foo': '1.2.3'}).validate();
        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dev_dependencies': {'foo': '1.2.3'}
          })
        ]).validate();
      });

      test('if package is added with a version constraint range', () async {
        await servePackages((builder) {
          builder.serve('foo', '1.2.3');
          builder.serve('foo', '1.2.2');
        });

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dev_dependencies': {'foo': '1.2.2'}
          })
        ]).create();

        await pubAdd(args: ['foo:>=1.2.2', '--dev']);

        await d.cacheDir({'foo': '1.2.3'}).validate();
        await d.appPackagesFile({'foo': '1.2.3'}).validate();
        await d.appPackagesFile({'foo': '1.2.3'}).validate();
        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dev_dependencies': {'foo': '>=1.2.2'}
          })
        ]).validate();
      });
    });

    group('dependency override', () {
      test('passes if package does not specify a range', () async {
        await servePackages((builder) {
          builder.serve('foo', '1.2.3');
          builder.serve('foo', '1.2.2');
        });

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dev_dependencies': {},
            'dependency_overrides': {'foo': '1.2.2'}
          })
        ]).create();

        await pubAdd(args: ['foo', '--dev']);

        await d.cacheDir({'foo': '1.2.2'}).validate();
        await d.appPackagesFile({'foo': '1.2.2'}).validate();
        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dev_dependencies': {'foo': '^1.2.2'},
            'dependency_overrides': {'foo': '1.2.2'}
          })
        ]).validate();
      });

      test('passes if constraint is git dependency', () async {
        await servePackages((builder) {
          builder.serve('foo', '1.2.3');
        });

        await d.git('foo.git',
            [d.libDir('foo'), d.libPubspec('foo', '1.2.3')]).create();

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dev_dependencies': {},
            'dependency_overrides': {
              'foo': {'git': '../foo.git'}
            }
          })
        ]).create();

        await pubAdd(args: ['foo:1.2.3', '--dev']);

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dev_dependencies': {'foo': '1.2.3'},
            'dependency_overrides': {
              'foo': {'git': '../foo.git'}
            }
          })
        ]).validate();
      });

      test('passes if constraint matches path dependency override', () async {
        await servePackages((builder) {
          builder.serve('foo', '1.2.2');
        });
        await d.dir(
            'foo', [d.libDir('foo'), d.libPubspec('foo', '1.2.2')]).create();

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dev_dependencies': {},
            'dependency_overrides': {
              'foo': {'path': '../foo'}
            }
          })
        ]).create();

        await pubAdd(args: ['foo:1.2.2', '--dev']);

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dev_dependencies': {'foo': '1.2.2'},
            'dependency_overrides': {
              'foo': {'path': '../foo'}
            }
          })
        ]).validate();
      });

      test('fails if constraint does not match override', () async {
        await servePackages((builder) {
          builder.serve('foo', '1.2.3');
          builder.serve('foo', '1.2.2');
        });

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dev_dependencies': {},
            'dependency_overrides': {'foo': '1.2.2'}
          })
        ]).create();

        await pubAdd(
            args: ['foo:1.2.3', '--dev'],
            exitCode: exit_codes.DATA,
            error: contains(
                '"foo" resolved to "1.2.2" which does not satisfy constraint '
                '"1.2.3". This could be caused by "dependency_overrides".'));

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dev_dependencies': {},
            'dependency_overrides': {'foo': '1.2.2'}
          }),
          d.nothing('.dart_tool/package_config.json'),
          d.nothing('pubspec.lock'),
          d.nothing('.packages'),
        ]).validate();
      });

      test('fails if constraint matches git dependency override', () async {
        await servePackages((builder) {
          builder.serve('foo', '1.2.3');
        });

        await d.git('foo.git',
            [d.libDir('foo'), d.libPubspec('foo', '1.0.0')]).create();

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dev_dependencies': {},
            'dependency_overrides': {
              'foo': {'git': '../foo.git'}
            }
          })
        ]).create();

        await pubAdd(
            args: ['foo:1.2.3'],
            exitCode: exit_codes.DATA,
            error: contains(
                '"foo" resolved to "1.0.0" which does not satisfy constraint '
                '"1.2.3". This could be caused by "dependency_overrides".'));

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dev_dependencies': {},
            'dependency_overrides': {
              'foo': {'git': '../foo.git'}
            }
          }),
          d.nothing('.dart_tool/package_config.json'),
          d.nothing('pubspec.lock'),
          d.nothing('.packages'),
        ]).validate();
      });

      test('fails if constraint does not match path dependency override',
          () async {
        await servePackages((builder) {
          builder.serve('foo', '1.2.2');
        });
        await d.dir(
            'foo', [d.libDir('foo'), d.libPubspec('foo', '1.0.0')]).create();

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dev_dependencies': {},
            'dependency_overrides': {
              'foo': {'path': '../foo'}
            }
          })
        ]).create();

        await pubAdd(
            args: ['foo:1.2.2', '--dev'],
            exitCode: exit_codes.DATA,
            error: contains(
                '"foo" resolved to "1.0.0" which does not satisfy constraint '
                '"1.2.2". This could be caused by "dependency_overrides".'));

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dev_dependencies': {},
            'dependency_overrides': {
              'foo': {'path': '../foo'}
            }
          }),
          d.nothing('.dart_tool/package_config.json'),
          d.nothing('pubspec.lock'),
          d.nothing('.packages'),
        ]).validate();
      });
    });

    test(
        'prints information saying that package is already a dependency if it '
        'already exists and exits with a usage exception', () async {
      await servePackages((builder) {
        builder.serve('foo', '1.2.3');
        builder.serve('foo', '1.2.2');
      });

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependencies': {'foo': '1.2.2'},
          'dev_dependencies': {}
        })
      ]).create();

      await pubAdd(
          args: ['foo:1.2.3', '--dev'],
          error: allOf([
            contains('"foo" is already in "dependencies". Please use '
                '"pub remove foo" to remove it'),
            contains('before adding it to "dev_dependencies"')
          ]),
          exitCode: exit_codes.USAGE);

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependencies': {'foo': '1.2.2'},
          'dev_dependencies': {}
        }),
        d.nothing('.dart_tool/package_config.json'),
        d.nothing('pubspec.lock'),
        d.nothing('.packages'),
      ]).validate();
    });
  });
}
