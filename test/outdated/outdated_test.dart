// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';
import '../descriptor.dart' as d;
import '../golden_file.dart';
import '../test_pub.dart';

/// Try running 'pub outdated' with a number of different sets of arguments.
///
/// Compare the stdout and stderr output to the file in goldens/$[name].
Future<void> variations(String name, {Map<String, String> environment}) async {
  final buffer = StringBuffer();
  for (final args in [
    ['outdated', '--json'],
    ['outdated', '--no-color'],
    ['outdated', '--no-color', '--no-transitive'],
    ['outdated', '--no-color', '--up-to-date'],
    ['outdated', '--no-color', '--prereleases'],
    ['outdated', '--no-color', '--no-dev-dependencies'],
    ['outdated', '--no-color', '--no-dependency-overrides'],
    ['outdated', '--no-color', '--mode=null-safety'],
    ['outdated', '--no-color', '--mode=null-safety', '--transitive'],
    ['outdated', '--no-color', '--mode=null-safety', '--no-prereleases'],
    ['outdated', '--json', '--mode=null-safety'],
    ['outdated', '--json', '--no-dev-dependencies'],
  ]) {
    await runPubIntoBuffer(args, buffer, environment: environment);
  }
  // The easiest way to update the golden files is to delete them and rerun the
  // test.
  expectMatchesGoldenFile(buffer.toString(), 'test/outdated/goldens/$name.txt');
}

Future<void> main() async {
  test('help text', () async {
    final buffer = StringBuffer();
    await runPubIntoBuffer(
      ['outdated', '--help'],
      buffer,
    );
    expectMatchesGoldenFile(
        buffer.toString(), 'test/outdated/goldens/helptext.txt');
  });

  test('no pubspec', () async {
    await d.dir(appPath, []).create();
    final buffer = StringBuffer();
    await runPubIntoBuffer(['outdated'], buffer);
    expectMatchesGoldenFile(
        buffer.toString(), 'test/outdated/goldens/no_pubspec.txt');
  });

  test('no lockfile', () async {
    await d.appDir({'foo': '^1.0.0', 'bar': '^1.0.0'}).create();
    await servePackages((builder) => builder
      ..serve('foo', '1.2.3')
      ..serve('bar', '1.2.3')
      ..serve('bar', '2.0.0'));
    await variations('no_lockfile');
  });

  test('no dependencies', () async {
    await d.appDir().create();
    await pubGet();
    await variations('no_dependencies');
  });

  test('newer versions available', () async {
    await servePackages((builder) => builder
      ..serve('foo', '1.2.3', deps: {'transitive': '^1.0.0'})
      ..serve('bar', '1.0.0')
      ..serve('builder', '1.2.3', deps: {
        'transitive': '^1.0.0',
        'dev_trans': '^1.0.0',
      })
      ..serve('transitive', '1.2.3')
      ..serve('dev_trans', '1.0.0'));

    await d.dir('local_package', [
      d.libDir('local_package'),
      d.libPubspec('local_package', '0.0.1')
    ]).create();

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {
          'foo': '^1.0.0',
          'bar': '^1.0.0',
          'local_package': {'path': '../local_package'}
        },
        'dev_dependencies': {'builder': '^1.0.0'},
      })
    ]).create();
    await pubGet();
    globalPackageServer.add((builder) => builder
      ..serve('foo', '1.3.0', deps: {'transitive': '>=1.0.0<3.0.0'})
      ..serve('foo', '2.0.0',
          deps: {'transitive': '>=1.0.0<3.0.0', 'transitive2': '^1.0.0'})
      ..serve('foo', '3.0.0', deps: {'transitive': '^2.0.0'})
      ..serve('builder', '1.3.0', deps: {'transitive': '^1.0.0'})
      ..serve('builder', '2.0.0', deps: {
        'transitive': '^1.0.0',
        'transitive3': '^1.0.0',
        'dev_trans': '^1.0.0'
      })
      ..serve('builder', '3.0.0-alpha', deps: {'transitive': '^1.0.0'})
      ..serve('transitive', '1.3.0')
      ..serve('transitive', '2.0.0')
      ..serve('transitive2', '1.0.0')
      ..serve('transitive3', '1.0.0')
      ..serve('dev_trans', '2.0.0'));
    await variations('newer_versions');
  });

  test('circular dependency on root', () async {
    await servePackages(
      (builder) => builder..serve('foo', '1.2.3', deps: {'app': '^1.0.0'}),
    );

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'version': '1.0.1',
        'dependencies': {
          'foo': '^1.0.0',
        },
      })
    ]).create();

    await pubGet();

    globalPackageServer.add(
      (builder) => builder..serve('foo', '1.3.0', deps: {'app': '^1.0.1'}),
    );
    await variations('circular_dependencies');
  });

  test('mutually incompatible newer versions', () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'version': '1.0.1',
        'dependencies': {
          'foo': '^1.0.0',
          'bar': '^1.0.0',
        },
      })
    ]).create();

    await servePackages((builder) => builder
      ..serve('foo', '1.0.0', deps: {'bar': '^1.0.0'})
      ..serve('bar', '1.0.0', deps: {'foo': '^1.0.0'})
      ..serve('foo', '2.0.0', deps: {'bar': '^1.0.0'})
      ..serve('bar', '2.0.0', deps: {'foo': '^1.0.0'}));
    await pubGet();

    await variations('mutually_incompatible');
  });

  test('null safety compliance', () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'version': '1.0.1',
        'dependencies': {
          'foo': '^1.0.0',
          'bar': '^1.0.0',
          'file_opts_out': '^1.0.0',
          'fails_analysis': '^1.0.0',
          'file_in_dependency_opts_out': '^1.0.0',
          'fails_analysis_in_dependency': '^1.0.0',
        },
        'environment': {'sdk': '>=2.12.0 < 3.0.0'},
      }),
    ]).create();

    await servePackages(
      (builder) => builder
        ..serve('foo', '1.0.0', deps: {
          'bar': '^1.0.0'
        }, pubspec: {
          'environment': {'sdk': '>=2.9.0 < 3.0.0'}
        })
        ..serve('bar', '1.0.0', pubspec: {
          'environment': {'sdk': '>=2.9.0 < 3.0.0'}
        })
        ..serve('foo', '2.0.0-nullsafety.0', deps: {
          'bar': '^2.0.0'
        }, pubspec: {
          'environment': {'sdk': '>=2.12.0 < 3.0.0'}
        })
        ..serve('foo', '2.0.0', deps: {
          'bar': '^1.0.0'
        }, pubspec: {
          'environment': {'sdk': '>=2.12.0 < 3.0.0'}
        })
        ..serve('bar', '2.0.0', pubspec: {
          'environment': {'sdk': '>=2.13.0 < 3.0.0'}
        })
        ..serve('file_opts_out', '1.0.0', pubspec: {
          'environment': {'sdk': '>=2.12.0 < 3.0.0'},
        }, contents: [
          d.dir('lib', [d.file('main.dart', '// @dart = 2.9\n')])
        ])
        ..serve('file_opts_out', '2.0.0', pubspec: {
          'environment': {'sdk': '>=2.12.0 < 3.0.0'},
        })
        ..serve('fails_analysis', '1.0.0', pubspec: {
          'environment': {'sdk': '>=2.12.0 < 3.0.0'},
        }, contents: [
          d.dir('lib', [d.file('main.dart', 'syntax error\n')])
        ])
        ..serve('fails_analysis', '2.0.0', pubspec: {
          'environment': {'sdk': '>=2.12.0 < 3.0.0'},
        })
        ..serve('file_in_dependency_opts_out', '1.0.0', deps: {
          'file_opts_out': '^1.0.0'
        }, pubspec: {
          'environment': {'sdk': '>=2.12.0 < 3.0.0'},
        })
        ..serve('file_in_dependency_opts_out', '2.0.0', pubspec: {
          'environment': {'sdk': '>=2.12.0 < 3.0.0'},
        })
        ..serve('fails_analysis_in_dependency', '1.0.0', deps: {
          'fails_analysis': '^1.0.0'
        }, pubspec: {
          'environment': {'sdk': '>=2.12.0 < 3.0.0'},
        })
        ..serve('fails_analysis_in_dependency', '2.0.0', pubspec: {
          'environment': {'sdk': '>=2.12.0 < 3.0.0'},
        }),
    );
    await pubGet(environment: {'_PUB_TEST_SDK_VERSION': '2.13.0'});

    await variations('null_safety',
        environment: {'_PUB_TEST_SDK_VERSION': '2.13.0'});
  });

  test('null-safety no resolution', () async {
    await servePackages((builder) => builder
      ..serve('foo', '1.0.0', pubspec: {
        'environment': {'sdk': '>=2.9.0 < 3.0.0'}
      })
      ..serve('foo', '2.0.0-nullsafety.0', deps: {
        'bar': '^1.0.0'
      }, pubspec: {
        'environment': {'sdk': '>=2.12.0 < 3.0.0'}
      })
      ..serve('bar', '1.0.0', pubspec: {
        'environment': {'sdk': '>=2.9.0 < 3.0.0'}
      })
      ..serve('bar', '2.0.0-nullsafety.0', deps: {
        'foo': '^1.0.0'
      }, pubspec: {
        'environment': {'sdk': '>=2.12.0 < 3.0.0'}
      }));

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'version': '1.0.0',
        'dependencies': {
          'foo': '^1.0.0',
          'bar': '^1.0.0',
        },
        'environment': {'sdk': '>=2.12.0 < 3.0.0'},
      }),
    ]).create();

    await pubGet(environment: {'_PUB_TEST_SDK_VERSION': '2.13.0'});

    await variations('null_safety_no_resolution',
        environment: {'_PUB_TEST_SDK_VERSION': '2.13.0'});
  });

  test('null-safety already migrated', () async {
    await servePackages((builder) => builder
      ..serve('foo', '1.0.0', pubspec: {
        'environment': {'sdk': '>=2.9.0 < 3.0.0'}
      })
      ..serve('foo', '2.0.0', pubspec: {
        'environment': {'sdk': '>=2.12.0 < 3.0.0'}
      })
      ..serve('bar', '1.0.0', pubspec: {
        'environment': {'sdk': '>=2.9.0 < 3.0.0'}
      })
      ..serve('bar', '2.0.0', deps: {
        'devTransitive': '^1.0.0'
      }, pubspec: {
        'environment': {'sdk': '>=2.12.0 < 3.0.0'}
      })
      ..serve('devTransitive', '1.0.0', pubspec: {
        'environment': {'sdk': '>=2.9.0 < 3.0.0'}
      }));

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'version': '1.0.0',
        'dependencies': {
          'foo': '^2.0.0',
        },
        'dev_dependencies': {
          'bar': '^2.0.0',
        },
        'environment': {'sdk': '>=2.12.0 < 3.0.0'},
      }),
    ]).create();

    await pubGet(environment: {'_PUB_TEST_SDK_VERSION': '2.13.0'});

    await variations('null_safety_already_migrated',
        environment: {'_PUB_TEST_SDK_VERSION': '2.13.0'});
  });

  test('overridden dependencies', () async {
    ensureGit();
    await servePackages(
      (builder) => builder
        ..serve('foo', '1.0.0')
        ..serve('foo', '2.0.0', deps: {'bar': '^1.0.0'})
        ..serve('bar', '1.0.0')
        ..serve('bar', '2.0.0')
        ..serve('baz', '1.0.0')
        ..serve('baz', '2.0.0'),
    );

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
            'git': {'url': '../foo.git'}
          },
          'bar': {'path': '../bar'},
          'baz': '2.0.0'
        },
      })
    ]).create();

    await pubGet();

    await variations('dependency_overrides');
  });

  test('overridden dependencies - no resolution', () async {
    ensureGit();
    await servePackages(
      (builder) => builder
        ..serve('foo', '1.0.0', deps: {'bar': '^2.0.0'})
        ..serve('foo', '2.0.0', deps: {'bar': '^1.0.0'})
        ..serve('bar', '1.0.0', deps: {'foo': '^1.0.0'})
        ..serve('bar', '2.0.0', deps: {'foo': '^2.0.0'}),
    );

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
      })
    ]).create();

    await pubGet();

    await variations('dependency_overrides_no_solution');
  });

  test(
      'latest version reported while locked on a prerelease can be a prerelease',
      () async {
    await servePackages((builder) => builder
      ..serve('foo', '0.9.0')
      ..serve('foo', '1.0.0-dev.1')
      ..serve('foo', '1.0.0-dev.2')
      ..serve('bar', '0.9.0')
      ..serve('bar', '1.0.0-dev.1')
      ..serve('bar', '1.0.0-dev.2')
      ..serve('mop', '0.10.0-dev')
      ..serve('mop', '0.10.0')
      ..serve('mop', '1.0.0-dev'));
    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'version': '1.0.1',
        'dependencies': {
          'foo': '1.0.0-dev.1',
          'bar': '^0.9.0',
          'mop': '0.10.0-dev'
        },
      })
    ]).create();

    await pubGet();

    await variations('prereleases');
  });

  test('Handles SDK dependencies', () async {
    await servePackages((builder) => builder
      ..serve('foo', '1.0.0', pubspec: {
        'environment': {'sdk': '>=2.10.0 <3.0.0'}
      })
      ..serve('foo', '1.1.0', pubspec: {
        'environment': {'sdk': '>=2.10.0 <3.0.0'}
      })
      ..serve('foo', '2.0.0', pubspec: {
        'environment': {'sdk': '>=2.12.0 <3.0.0'}
      }));

    await d.dir('flutter-root', [
      d.file('version', '1.2.3'),
      d.dir('packages', [
        d.dir('flutter', [
          d.libPubspec('flutter', '1.0.0', sdk: '>=2.12.0 <3.0.0'),
        ]),
        d.dir('flutter_test', [
          d.libPubspec('flutter_test', '1.0.0', sdk: '>=2.10.0 <3.0.0'),
        ]),
      ]),
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
      })
    ]).create();

    await pubGet(environment: {
      'FLUTTER_ROOT': d.path('flutter-root'),
      '_PUB_TEST_SDK_VERSION': '2.13.0'
    });

    await variations('handles_sdk_dependencies', environment: {
      'FLUTTER_ROOT': d.path('flutter-root'),
      '_PUB_TEST_SDK_VERSION': '2.13.0',
      // To test that the reproduction command is reflected correctly.
      'PUB_ENVIRONMENT': 'flutter_cli:get',
    });
  });

  test("doesn't allow arguments. Handles bad flags", () async {
    final sb = StringBuffer();
    await runPubIntoBuffer(['outdated', 'random_argument'], sb);
    await runPubIntoBuffer(['outdated', '--bad_flag'], sb);
    expectMatchesGoldenFile(
        sb.toString(), 'test/outdated/goldens/bad_arguments.txt');
  });
}
