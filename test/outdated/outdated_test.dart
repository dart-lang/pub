// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../descriptor.dart' as d;
import '../golden_file.dart';
import '../package_server.dart';
import '../test_pub.dart';

extension on GoldenTestContext {
  /// Try running 'pub outdated' with a number of different sets of arguments.
  /// And compare to results from test/testdata/goldens/...
  Future<void> runOutdatedTests({
    Map<String, String>? environment,
    String? workingDirectory,
  }) async {
    const commands = [
      ['outdated', '--json'],
      ['outdated', '--no-color'],
      ['outdated', '--no-color', '--no-transitive'],
      ['outdated', '--no-color', '--up-to-date'],
      ['outdated', '--no-color', '--prereleases'],
      ['outdated', '--no-color', '--no-dev-dependencies'],
      ['outdated', '--no-color', '--no-dependency-overrides'],
      ['outdated', '--json', '--no-dev-dependencies'],
    ];
    for (final args in commands) {
      await run(
        args,
        environment: environment,
        workingDirectory: workingDirectory,
      );
    }
  }
}

Future<void> main() async {
  testWithGolden('no pubspec', (ctx) async {
    await d.dir(appPath, []).create();
    await ctx.run(['outdated']);
  });

  testWithGolden('no lockfile', (ctx) async {
    await d.appDir(dependencies: {'foo': '^1.0.0', 'bar': '^1.0.0'}).create();
    await servePackages()
      ..serve('foo', '1.2.3')
      ..serve('bar', '1.2.3')
      ..serve('bar', '2.0.0');

    await ctx.runOutdatedTests();
  });

  testWithGolden('no dependencies', (ctx) async {
    await d.appDir().create();
    await pubGet();

    await ctx.runOutdatedTests();
  });

  testWithGolden('newer versions available', (ctx) async {
    final builder = await servePackages();
    builder
      ..serve('foo', '1.2.3', deps: {'transitive': '^1.0.0'})
      ..serve('bar', '1.0.0')
      ..serve(
        'builder',
        '1.2.3',
        deps: {
          'transitive': '^1.0.0',
          'dev_trans': '^1.0.0',
        },
      )
      ..serve('transitive', '1.2.3')
      ..serve('dev_trans', '1.0.0')
      ..serve('retracted', '1.0.0')
      ..serve('retracted', '1.0.1');

    await d.dir('local_package', [
      d.libDir('local_package'),
      d.libPubspec('local_package', '0.0.1'),
    ]).create();

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {
          'foo': '^1.0.0',
          'bar': '^1.0.0',
          'local_package': {'path': '../local_package'},
          'retracted': '^1.0.0',
        },
        'dev_dependencies': {'builder': '^1.0.0'},
      }),
    ]).create();
    await pubGet();
    builder
      ..serve('foo', '1.3.0', deps: {'transitive': '>=1.0.0<3.0.0'})
      ..serve(
        'foo',
        '2.0.0',
        deps: {'transitive': '>=1.0.0<3.0.0', 'transitive2': '^1.0.0'},
      )
      ..serve('foo', '3.0.0', deps: {'transitive': '^2.0.0'})
      ..serve('builder', '1.3.0', deps: {'transitive': '^1.0.0'})
      ..serve(
        'builder',
        '2.0.0',
        deps: {
          'transitive': '^1.0.0',
          'transitive3': '^1.0.0',
          'dev_trans': '^1.0.0',
        },
      )
      ..serve('builder', '3.0.0-alpha', deps: {'transitive': '^1.0.0'})
      ..serve('transitive', '1.3.0')
      ..serve('transitive', '2.0.0')
      ..serve('transitive2', '1.0.0')
      ..serve('transitive3', '1.0.0')
      ..serve('dev_trans', '2.0.0')
      // Even though the current (and latest) version is retracted, it should be
      // the one shown in the upgradable and resolvable columns.
      ..retractPackageVersion('retracted', '1.0.1');
    await ctx.runOutdatedTests();
  });

  testWithGolden('show discontinued', (ctx) async {
    final builder = await servePackages();
    builder
      ..serve('foo', '1.2.3', deps: {'transitive': '^1.0.0'})
      ..serve('bar', '1.0.0')
      ..serve('baz', '1.0.0')
      ..serve('transitive', '1.2.3');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {
          'foo': '^1.0.0',
          'bar': '^1.0.0',
          'baz': '^1.0.0',
        },
      }),
    ]).create();
    await pubGet();
    builder.discontinue('foo');
    builder.discontinue('baz', replacementText: 'newbaz');
    await ctx.runOutdatedTests();
  });

  testWithGolden('show discontinued with no latest version', (ctx) async {
    final builder = await servePackages();
    builder
      ..serve('foo', '1.2.3', deps: {'transitive': '^1.0.0'})
      ..serve('bar', '1.0.0')
      ..serve('baz', '1.0.0')
      ..serve('transitive', '1.2.3');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {
          'foo': '^1.0.0',
          'bar': '^1.0.0',
          'baz': '^1.0.0',
        },
      }),
    ]).create();
    await pubGet();
    builder.retractPackageVersion('foo', '1.2.3');
    builder.discontinue('foo');
    builder.discontinue('baz', replacementText: 'newbaz');
    await ctx.runOutdatedTests();
  });

  testWithGolden('show retracted', (ctx) async {
    final builder = await servePackages();
    builder
      ..serve('foo', '1.0.0', deps: {'transitive': '^1.0.0'})
      ..serve('transitive', '1.2.3');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {
          'foo': '^1.0.0',
        },
      }),
    ]).create();
    await pubGet();
    builder.retractPackageVersion('foo', '1.0.0');
    builder.serve('foo', '1.2.0');
    await ctx.runOutdatedTests();
  });

  testWithGolden("don't show retracted", (ctx) async {
    final builder = await servePackages();
    builder
      ..serve('foo', '1.0.0', deps: {'transitive': '^1.0.0'})
      ..serve('transitive', '1.2.3');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {
          'foo': '^1.0.0',
        },
      }),
    ]).create();
    await pubGet();
    builder.retractPackageVersion('foo', '1.0.0');
    builder.serve('foo', '1.2.0');
    await pubUpgrade();
    await ctx.runOutdatedTests();
  });

  testWithGolden('show discontinued and retracted', (ctx) async {
    final builder = await servePackages();
    builder
      ..serve('foo', '1.0.0', deps: {'transitive': '^1.0.0'})
      ..serve('bar', '1.0.0', deps: {'transitive': '^1.0.0'})
      ..serve('transitive', '1.2.3');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {
          'foo': '^1.0.0',
          'bar': '^1.0.0',
        },
      }),
    ]).create();
    await pubGet();
    builder.discontinue('foo');
    builder.retractPackageVersion('foo', '1.0.0');
    builder.discontinue('bar');
    builder.retractPackageVersion('bar', '1.0.0');
    builder.serve('foo', '1.2.0', deps: {'transitive': '^1.0.0'});
    await pubGet();
    await ctx.runOutdatedTests();
  });

  testWithGolden('circular dependency on root', (ctx) async {
    final server = await servePackages();
    server.serve('foo', '1.2.3', deps: {'app': '^1.0.0'});

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'version': '1.0.1',
        'dependencies': {
          'foo': '^1.0.0',
        },
      }),
    ]).create();

    await pubGet();

    server.serve('foo', '1.3.0', deps: {'app': '^1.0.1'});
    await ctx.runOutdatedTests();
  });

  testWithGolden('mutually incompatible newer versions', (ctx) async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'version': '1.0.1',
        'dependencies': {
          'foo': '^1.0.0',
          'bar': '^1.0.0',
        },
      }),
    ]).create();

    await servePackages()
      ..serve('foo', '1.0.0', deps: {'bar': '^1.0.0'})
      ..serve('bar', '1.0.0', deps: {'foo': '^1.0.0'})
      ..serve('foo', '2.0.0', deps: {'bar': '^1.0.0'})
      ..serve('bar', '2.0.0', deps: {'foo': '^1.0.0'});
    await pubGet();

    await ctx.runOutdatedTests();
  });

  testWithGolden('overridden dependencies', (ctx) async {
    ensureGit();
    await servePackages()
      ..serve('foo', '1.0.0')
      ..serve('foo', '2.0.0', deps: {'bar': '^1.0.0'})
      ..serve('bar', '1.0.0')
      ..serve('bar', '2.0.0')
      ..serve('baz', '1.0.0')
      ..serve('baz', '2.0.0');

    await d.git('foo.git', [
      d.libPubspec('foo', '1.0.1'),
    ]).create();

    await d.dir('bar', [
      d.libPubspec('bar', '1.0.1'),
    ]).create();

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'version': '1.0.1',
        'dependencies': {
          'foo': '^1.0.0',
          'bar': '^2.0.0',
          'baz': '^1.0.0',
        },
        'dependency_overrides': {
          'foo': {
            'git': {'url': '../foo.git'},
          },
          'bar': {'path': '../bar'},
          'baz': '2.0.0',
        },
      }),
    ]).create();

    await pubGet();

    await ctx.runOutdatedTests();
  });

  testWithGolden('overridden dependencies - no resolution', (ctx) async {
    ensureGit();
    await servePackages()
      ..serve('foo', '1.0.0', deps: {'bar': '^2.0.0'})
      ..serve('foo', '2.0.0', deps: {'bar': '^1.0.0'})
      ..serve('bar', '1.0.0', deps: {'foo': '^1.0.0'})
      ..serve('bar', '2.0.0', deps: {'foo': '^2.0.0'});

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'version': '1.0.1',
        'dependencies': {
          'foo': 'any',
          'bar': 'any',
        },
        'dependency_overrides': {
          'foo': '1.0.0',
          'bar': '1.0.0',
        },
      }),
    ]).create();

    await pubGet();

    await ctx.runOutdatedTests();
  });

  testWithGolden('overridden dependencies with retraction- no resolution ',
      (ctx) async {
    ensureGit();
    final builder = await servePackages()
      ..serve('foo', '1.0.0', deps: {'bar': '^2.0.0'})
      ..serve('foo', '2.0.0', deps: {'bar': '^1.0.0'})
      ..serve('bar', '1.0.0', deps: {'foo': '^1.0.0'})
      ..serve('bar', '2.0.0', deps: {'foo': '^2.0.0'});

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'version': '1.0.1',
        'dependencies': {
          'foo': 'any',
          'bar': 'any',
        },
        'dependency_overrides': {
          'foo': '1.0.0',
          'bar': '1.0.0',
        },
      }),
    ]).create();

    await pubGet();

    builder.retractPackageVersion('bar', '1.0.0');
    await ctx.runOutdatedTests();
  });

  testWithGolden('do not report ignored advisories', (ctx) async {
    final builder = await servePackages();
    builder
      ..serve('foo', '1.0.0', deps: {'transitive': '^1.0.0'})
      ..serve('transitive', '1.2.3');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {
          'foo': '^1.0.0',
        },
        'ignored_advisories': ['ABCD-1234-5678-9101', '1234-ABCD-EFGH-IJKL'],
      }),
    ]).create();
    await pubGet();

    builder.addAdvisory(
      advisoryId: 'ABCD-1234-5678-9101',
      displayUrl: 'https://github.com/advisories/ABCD-1234-5678-9101',
      affectedPackages: [
        AffectedPackage(
          name: 'foo',
          versions: ['1.0.0'],
        ),
      ],
    );

    builder.addAdvisory(
      advisoryId: 'EFGH-0000-1111-2222',
      displayUrl: 'https://github.com/advisories/EFGH-0000-1111-2222',
      aliases: ['1234-ABCD-EFGH-IJKL'],
      affectedPackages: [
        AffectedPackage(
          name: 'foo',
          versions: ['1.0.0'],
        ),
      ],
    );

    builder.serve('foo', '1.2.0');
    await ctx.runOutdatedTests();
  });

  testWithGolden('only report unignored advisory', (ctx) async {
    final builder = await servePackages();
    builder
      ..serve('foo', '1.0.0', deps: {'transitive': '^1.0.0'})
      ..serve('transitive', '1.2.3');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {
          'foo': '^1.0.0',
        },
        'ignored_advisories': ['ABCD-1234-5678-9101', '1234-ABCD-EFGH-IJKL'],
      }),
    ]).create();
    await pubGet();

    builder.addAdvisory(
      advisoryId: 'ABCD-1234-5678-9101',
      displayUrl: 'https://github.com/advisories/ABCD-1234-5678-9101',
      affectedPackages: [
        AffectedPackage(
          name: 'foo',
          versions: ['1.0.0'],
        ),
      ],
    );

    builder.addAdvisory(
      advisoryId: 'EFGH-0000-1111-2222',
      aliases: ['1234-ABCD-EFGH-IJKL'],
      displayUrl: 'https://github.com/advisories/EFGH-0000-1111-2222',
      affectedPackages: [
        AffectedPackage(
          name: 'foo',
          versions: ['1.0.0'],
        ),
      ],
    );

    builder.addAdvisory(
      advisoryId: 'VXYZ-1234-5678-9101',
      displayUrl: 'https://github.com/advisories/VXYZ-1234-5678-9101',
      affectedPackages: [
        AffectedPackage(
          name: 'foo',
          versions: ['1.0.0'],
        ),
      ],
    );

    builder.serve('foo', '1.2.0');
    await ctx.runOutdatedTests();
  });

  testWithGolden('do not show advisories if no version is affected',
      (ctx) async {
    final builder = await servePackages();
    builder
      ..serve('foo', '1.0.0', deps: {'transitive': '^1.0.0'})
      ..serve('transitive', '1.2.3');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {
          'foo': '^1.0.0',
        },
      }),
    ]).create();
    await pubGet();

    builder.addAdvisory(
      advisoryId: 'ABCD-1234-5678-9101',
      displayUrl: 'https://github.com/advisories/ABCD-1234-5678-9101',
      affectedPackages: [
        AffectedPackage(
          name: 'foo',
          versions: ['0.1.0'],
        ),
      ],
    );

    builder.serve('foo', '1.2.0');
    await ctx.runOutdatedTests();
  });

  testWithGolden('show advisory - current', (ctx) async {
    final builder = await servePackages();
    builder
      ..serve('foo', '1.0.0', deps: {'transitive': '^1.0.0'})
      ..serve('transitive', '1.2.3');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {
          'foo': '^1.0.0',
        },
      }),
    ]).create();
    await pubGet();

    builder.addAdvisory(
      advisoryId: 'ABCD-1234-5678-9101',
      displayUrl: 'https://github.com/advisories/ABCD-1234-5678-9101',
      affectedPackages: [
        AffectedPackage(
          name: 'foo',
          versions: ['1.0.0'],
        ),
      ],
    );

    builder.serve('foo', '1.2.0');
    await ctx.runOutdatedTests();
  });

  testWithGolden('show advisory - current, same package mentioned twice',
      (ctx) async {
    final builder = await servePackages();
    builder
      ..serve('foo', '1.0.0', deps: {'transitive': '^1.0.0'})
      ..serve('transitive', '1.2.3');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {
          'foo': '^1.0.0',
        },
      }),
    ]).create();
    await pubGet();

    builder.addAdvisory(
      advisoryId: 'ABCD-1234-5678-9101',
      displayUrl: 'https://github.com/advisories/ABCD-1234-5678-9101',
      affectedPackages: [
        AffectedPackage(
          name: 'foo',
          versions: ['0.0.1'],
        ),
        AffectedPackage(
          name: 'foo',
          versions: ['1.0.0'],
        ),
      ],
    );

    builder.serve('foo', '1.2.0');
    await ctx.runOutdatedTests();
  });

  testWithGolden('show advisory - current also retracted', (ctx) async {
    final builder = await servePackages();
    builder
      ..serve('foo', '1.0.0', deps: {'transitive': '^1.0.0'})
      ..serve('transitive', '1.2.3');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {
          'foo': '^1.0.0',
        },
      }),
    ]).create();
    await pubGet();

    builder.retractPackageVersion('foo', '1.0.0');

    builder.addAdvisory(
      advisoryId: 'ABCD-1234-5678-9101',
      displayUrl: 'https://github.com/advisories/ABCD-1234-5678-9101',
      affectedPackages: [
        AffectedPackage(
          name: 'foo',
          versions: ['1.0.0'],
        ),
      ],
    );

    builder.serve('foo', '1.2.0');
    await ctx.runOutdatedTests();
  });

  testWithGolden('show advisory - latest', (ctx) async {
    final builder = await servePackages();
    builder
      ..serve('foo', '1.0.0', deps: {'transitive': '^1.0.0'})
      ..serve('transitive', '1.2.3');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {
          'foo': '^1.0.0',
        },
      }),
    ]).create();
    await pubGet();

    builder.addAdvisory(
      advisoryId: 'ABCD-1234-5678-9101',
      displayUrl: 'https://github.com/advisories/ABCD-1234-5678-9101',
      affectedPackages: [
        AffectedPackage(
          name: 'foo',
          versions: ['1.2.0'],
        ),
      ],
    );

    builder.serve('foo', '1.2.0');
    await ctx.runOutdatedTests();
  });

  testWithGolden('show advisory - latest also discontinued', (ctx) async {
    final builder = await servePackages();
    builder
      ..serve('foo', '1.0.0', deps: {'transitive': '^1.0.0'})
      ..serve('transitive', '1.2.3');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {
          'foo': '^1.0.0',
        },
      }),
    ]).create();
    await pubGet();

    builder.discontinue('foo');
    builder.addAdvisory(
      advisoryId: 'ABCD-1234-5678-9101',
      displayUrl: 'https://github.com/advisories/ABCD-1234-5678-9101',
      affectedPackages: [
        AffectedPackage(
          name: 'foo',
          versions: ['1.2.0'],
        ),
      ],
    );

    builder.serve('foo', '1.2.0');
    await ctx.runOutdatedTests();
  });

  testWithGolden('show advisory - all versions', (ctx) async {
    final builder = await servePackages();
    builder
      ..serve('foo', '1.0.0', deps: {'transitive': '^1.0.0'})
      ..serve('transitive', '1.2.3');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {
          'foo': '^1.0.0',
        },
      }),
    ]).create();
    await pubGet();

    builder.addAdvisory(
      advisoryId: 'ABCD-1234-5678-9101',
      displayUrl: 'https://github.com/advisories/ABCD-1234-5678-9101',
      affectedPackages: [
        AffectedPackage(
          name: 'foo',
          versions: ['1.0.0', '1.2.0'],
        ),
      ],
    );

    builder.serve('foo', '1.2.0');
    await ctx.runOutdatedTests();
  });

  testWithGolden('show advisory - several advisories', (ctx) async {
    final builder = await servePackages();
    builder
      ..serve('foo', '1.0.0', deps: {'transitive': '^1.0.0'})
      ..serve('transitive', '1.2.3');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {
          'foo': '^1.0.0',
        },
      }),
    ]).create();
    await pubGet();

    builder.addAdvisory(
      advisoryId: 'ABCD-1234-5678-9101',
      displayUrl: 'https://github.com/advisories/ABCD-1234-5678-9101',
      affectedPackages: [
        AffectedPackage(
          name: 'foo',
          versions: ['1.0.0', '1.2.0'],
        ),
      ],
    );

    builder.addAdvisory(
      advisoryId: 'VXYZ-1234-5678-9101',
      displayUrl: 'https://github.com/advisories/VXYZ-1234-5678-9101',
      affectedPackages: [
        AffectedPackage(
          name: 'foo',
          versions: ['1.0.0'],
        ),
      ],
    );

    builder.serve('foo', '1.2.0');
    await ctx.runOutdatedTests();
  });

  testWithGolden(
      'latest version reported while locked on a prerelease can be a prerelease',
      (ctx) async {
    await servePackages()
      ..serve('foo', '0.9.0')
      ..serve('foo', '1.0.0-dev.1')
      ..serve('foo', '1.0.0-dev.2')
      ..serve('bar', '0.9.0')
      ..serve('bar', '1.0.0-dev.1')
      ..serve('bar', '1.0.0-dev.2')
      ..serve('mop', '0.10.0-dev')
      ..serve('mop', '0.10.0')
      ..serve('mop', '1.0.0-dev');
    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'version': '1.0.1',
        'dependencies': {
          'foo': '1.0.0-dev.1',
          'bar': '^0.9.0',
          'mop': '0.10.0-dev',
        },
      }),
    ]).create();

    await pubGet();

    await ctx.runOutdatedTests();
  });

  testWithGolden('reports dependencies from all of workspace', (ctx) async {
    final server = await servePackages();
    server.serve('myapp', '1.2.4');
    server.serve('dep', '0.9.0', deps: {'myapp': '^1.2.3'});
    server.serve('dep', '0.8.0', deps: {'myapp': '^1.2.3'});
    server.serve('dep', '1.0.0');
    server.serve('dep_a', '0.9.0');
    server.serve('dep_a', '1.0.0');
    server.serve('dev_dep_a', '0.9.0');
    server.serve('dev_dep_a', '1.0.0');

    await d.dir(appPath, [
      d.libPubspec(
        'myapp',
        '1.2.3',
        deps: {'dep': '^0.9.0'},
        extras: {
          'workspace': ['pkgs/a'],
        },
        sdk: '^3.5.0',
      ),
      d.dir('pkgs', [
        d.dir('a', [
          d.libPubspec(
            'a',
            '1.1.1',
            deps: {'myapp': '^1.0.0', 'dep_a': '^0.9.0'},
            devDeps: {'dev_dep_a': '^0.9.0'},
            extras: {
              'dependency_overrides': {'dep': '0.8.0'},
            },
            resolutionWorkspace: true,
          ),
        ]),
      ]),
    ]).create();

    await pubGet(
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
    );

    server.serve('dep', '0.9.5');
    server.serve('dep_a', '0.9.5');
    server.serve('dev_dep_a', '0.9.5');

    await ctx.runOutdatedTests(
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
    );
  });

  testWithGolden('Handles SDK dependencies', (ctx) async {
    await servePackages()
      ..serve(
        'foo',
        '1.0.0',
        pubspec: {
          'environment': {'sdk': '>=2.10.0 <3.0.0'},
        },
      )
      ..serve(
        'foo',
        '1.1.0',
        pubspec: {
          'environment': {'sdk': '>=2.10.0 <3.0.0'},
        },
      )
      ..serve(
        'foo',
        '2.0.0',
        pubspec: {
          'environment': {'sdk': '>=2.12.0 <3.0.0'},
        },
      );

    await d.dir('flutter-root', [
      d.dir('packages', [
        d.dir('flutter', [
          d.libPubspec('flutter', '1.0.0', sdk: '>=2.12.0 <3.0.0'),
        ]),
        d.dir('flutter_test', [
          d.libPubspec('flutter_test', '1.0.0', sdk: '>=2.10.0 <3.0.0'),
        ]),
      ]),
      d.flutterVersion('1.2.3'),
    ]).create();

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'version': '1.0.1',
        'environment': {'sdk': '>=2.12.0 <3.0.0'},
        'dependencies': {
          'foo': '^1.0.0',
          'flutter': {
            'sdk': 'flutter',
          },
        },
        'dev_dependencies': {
          'foo': '^1.0.0',
          'flutter_test': {
            'sdk': 'flutter',
          },
        },
      }),
    ]).create();

    await pubGet(
      environment: {
        'FLUTTER_ROOT': d.path('flutter-root'),
        '_PUB_TEST_SDK_VERSION': '2.13.0',
      },
    );

    await ctx.runOutdatedTests(
      environment: {
        'FLUTTER_ROOT': d.path('flutter-root'),
        '_PUB_TEST_SDK_VERSION': '2.13.0',
        // To test that the reproduction command is reflected correctly.
        'PUB_ENVIRONMENT': 'flutter_cli:get',
      },
    );
  });

  testWithGolden('does not allow arguments - handles bad flags', (ctx) async {
    await ctx.run(['outdated', 'random_argument']);
    await ctx.run(['outdated', '--bad_flag']);
  });

  testWithGolden('Handles packages that are not found on server', (ctx) async {
    await servePackages();
    await d.appDir(
      dependencies: {'foo': 'any'},
      pubspec: {
        'dependency_overrides': {
          'foo': {'path': '../foo'},
        },
      },
    ).create();
    await d.dir('foo', [d.libPubspec('foo', '1.0.0')]).create();
    await ctx.run(['outdated']);
  });
}
