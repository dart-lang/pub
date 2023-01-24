// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:path/path.dart' as path;

import 'package:pub/src/exit_codes.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

d.DirectoryDescriptor package({
  String version = '1.0.0',
  Map? deps,
  String? sdk,
}) {
  return d.dir(appPath, [
    d.libPubspec(
      'test_pkg',
      version,
      sdk: sdk ?? defaultSdkConstraint,
      deps: deps,
    ),
    d.file('LICENSE', 'Eh, do what you want.'),
    d.file('README.md', "This package isn't real."),
    d.file('CHANGELOG.md', '# $version\nFirst version\n'),
    d.dir('lib', [d.file('test_pkg.dart', 'int i = 1;')])
  ]);
}

Future<void> expectValidation({
  error,
  int exitCode = 0,
  Map<String, String> environment = const {},
}) async {
  await runPub(
    error: error ?? contains('Package has 0 warnings.'),
    args: ['publish', '--dry-run'],
    // workingDirectory: d.path(appPath),
    exitCode: exitCode,
    environment: environment,
  );
}

Future<void> expectValidationWarning(
  error, {
  int count = 1,
  Map<String, String> environment = const {},
}) async {
  if (error is String) error = contains(error);
  await expectValidation(
    error: allOf([error, contains('Package has $count warning')]),
    exitCode: DATA,
    environment: environment,
  );
}

Future<void> expectValidationError(
  String text, {
  Map<String, String> environment = const {},
}) async {
  await expectValidation(
    error: allOf([
      contains(text),
      contains('Package validation found the following error:')
    ]),
    exitCode: DATA,
    environment: environment,
  );
}

Future<void> setUpDependency(
  dep, {
  String? sdk,
  List<String> hostedVersions = const [],
}) async {
  final server = await servePackages();
  for (final version in hostedVersions) {
    server.serve('foo', version);
  }

  await package(deps: {'foo': dep}, sdk: sdk).create();
}

void main() {
  group('should consider a package valid if it', () {
    test('looks normal', () async {
      await package().create();
      await expectValidation();
    });

    test('has a ^ constraint with an appropriate SDK constraint', () async {
      (await servePackages()).serve('foo', '1.2.3', sdk: '^1.8.3');
      await package(deps: {'foo': '^1.2.3'}, sdk: '^1.8.3').create();
      await expectValidation(environment: {'_PUB_TEST_SDK_VERSION': '1.18.0'});
    });

    test('with a dependency on a pre-release while being one', () async {
      (await servePackages()).serve('foo', '1.2.3-dev');
      await package(version: '1.0.0-dev', deps: {'foo': '^1.2.3-dev'}).create();
      await expectValidation();
    });

    test('has a git path dependency with an appropriate SDK constraint',
        () async {
      await servePackages();
      await d.git('foo', [
        d.dir('subdir', [d.libPubspec('foo', '1.0.0', sdk: '^2.0.0')]),
      ]).create();
      await package(
        deps: {
          'foo': {
            'git': {'url': '../foo', 'path': 'subdir'}
          }
        },
        sdk: '>=2.0.0 <3.0.0',
      ).create();

      // We should get a warning for using a git dependency, but not an error.
      await expectValidationWarning(
        allOf([
          contains('  foo: any'),
          contains("Publishable packages can't have 'git' dependencies"),
        ]),
        count: 2,
        environment: {'_PUB_TEST_SDK_VERSION': '2.0.0'},
      );
    });

    test('depends on Flutter from an SDK source', () async {
      await d.dir('flutter', [d.file('version', '1.2.3')]).create();
      await flutterPackage('flutter', sdk: '>=1.19.0 <2.0.0').create();
      await package(
        deps: {
          'flutter': {'sdk': 'flutter'}
        },
        sdk: '>=1.19.0 <2.0.0',
      ).create();

      await expectValidation(
        environment: {
          '_PUB_TEST_SDK_VERSION': '1.19.0',
          'FLUTTER_ROOT': path.join(d.sandbox, 'flutter')
        },
      );
    });

    test(
      'depends on a package from Flutter with an appropriate Dart SDK constraint',
      () async {
        await d.dir('flutter', [d.file('version', '1.2.3')]).create();
        await flutterPackage('foo', sdk: '^1.0.0').create();
        await d.dir('flutter', [d.file('version', '1.2.3')]).create();
        await package(
          deps: {
            'foo': {'sdk': 'flutter', 'version': '>=1.2.3 <2.0.0'},
          },
          sdk: '>=1.19.0 <2.0.0',
        ).create();

        await expectValidation(
          environment: {
            '_PUB_TEST_SDK_VERSION': '1.19.0',
            'FLUTTER_ROOT': path.join(d.sandbox, 'flutter'),
          },
        );
      },
    );

    test(
      'depends on a package from Fuchsia with an appropriate Dart SDK constraint',
      () async {
        await fuschiaPackage('foo', sdk: '>=2.0.0 <3.0.0').create();
        await package(
          sdk: '>=2.0.0 <3.0.0',
          deps: {
            'foo': {'sdk': 'fuchsia', 'version': '>=1.2.3 <2.0.0'}
          },
        ).create();

        await expectValidation(
          environment: {
            'FUCHSIA_DART_SDK_ROOT': path.join(d.sandbox, 'fuchsia'),
            '_PUB_TEST_SDK_VERSION': '2.12.0',
          },
        );
      },
    );
  });

  group('should consider a package invalid if it', () {
    setUp(package().create);

    group('has a path dependency', () {
      group('where a hosted version exists', () {
        test('and should suggest the hosted primary version', () async {
          await d.dir('foo', [
            d.libPubspec('foo', '1.2.3', sdk: 'any'),
          ]).create();
          await setUpDependency(
            sdk: '^1.8.0',
            {'path': path.join(d.sandbox, 'foo')},
            hostedVersions: ['3.0.0-pre', '2.0.0', '1.0.0'],
          );
          await expectValidationError(
            '  foo: ^2.0.0',
            environment: {'_PUB_TEST_SDK_VERSION': '1.8.0'},
          );
        });

        test(
            "and should suggest the hosted prerelease version if it's the only version available",
            () async {
          await d.dir('foo', [
            d.libPubspec('foo', '1.2.3', sdk: 'any'),
          ]).create();
          await setUpDependency(
            sdk: '^1.8.0',
            {'path': path.join(d.sandbox, 'foo')},
            hostedVersions: ['3.0.0-pre', '2.0.0-pre'],
          );
          await expectValidationError(
            '  foo: ^3.0.0-pre',
            environment: {'_PUB_TEST_SDK_VERSION': '1.8.0'},
          );
        });

        test('and should suggest a tighter constraint if primary is pre-1.0.0',
            () async {
          await d.dir('foo', [
            d.libPubspec('foo', '1.2.3', sdk: 'any'),
          ]).create();
          await setUpDependency(
            sdk: '^1.8.0',
            {'path': path.join(d.sandbox, 'foo')},
            hostedVersions: ['0.0.1', '0.0.2'],
          );
          await expectValidationError(
            '  foo: ^0.0.2',
            environment: {'_PUB_TEST_SDK_VERSION': '1.8.0'},
          );
        });
      });

      group('where no hosted version exists', () {
        test("and should use the other source's version", () async {
          await d.dir('foo', [
            d.libPubspec('foo', '1.2.3', sdk: 'any'),
          ]).create();
          await setUpDependency(sdk: '^1.8.0', {
            'path': path.join(d.sandbox, 'foo'),
            'version': '>=1.0.0 <2.0.0'
          });
          await expectValidationError(
            '  foo: ">=1.0.0 <2.0.0"',
            environment: {'_PUB_TEST_SDK_VERSION': '1.8.0'},
          );
        });

        test(
            "and should use the other source's unquoted version if "
            'concrete', () async {
          await d.dir('foo', [
            d.libPubspec('foo', '0.2.3', sdk: '^1.8.0'),
          ]).create();
          await setUpDependency(
            sdk: '^1.8.0',
            {'path': path.join(d.sandbox, 'foo'), 'version': '0.2.3'},
          );
          await expectValidationError(
            '  foo: 0.2.3',
            environment: {'_PUB_TEST_SDK_VERSION': '1.8.0'},
          );
        });
      });
    });

    group('has an unconstrained dependency', () {
      group('with a lockfile', () {
        test('and it should suggest a constraint based on the locked version',
            () async {
          (await servePackages()).serve('foo', '1.2.3');
          await d.dir(appPath, [
            d.libPubspec('test_pkg', '1.0.0', deps: {'foo': 'any'}),
          ]).create();

          await expectValidationWarning('  foo: ^1.2.3');
        });

        test(
            'and it should suggest a concrete constraint if the locked version is pre-1.0.0',
            () async {
          (await servePackages()).serve('foo', '0.1.2');

          await d.dir(appPath, [
            d.libPubspec('test_pkg', '1.0.0', deps: {'foo': 'any'}),
            d.file(
              'pubspec.lock',
              jsonEncode({
                'packages': {
                  'foo': {
                    'version': '0.1.2',
                    'source': 'hosted',
                    'description': {'name': 'foo', 'url': 'https://pub.dev'}
                  }
                }
              }),
            )
          ]).create();

          await expectValidationWarning('  foo: ^0.1.2');
        });
      });
    });

    test('with a dependency on a pre-release without being one', () async {
      (await servePackages()).serve('foo', '1.2.3-dev', sdk: '^1.8.0');

      await d.dir(appPath, [
        d.libPubspec(
          'test_pkg',
          '1.0.0',
          deps: {'foo': '^1.2.3-dev'},
          sdk: '>=1.8.0 <2.0.0',
        )
      ]).create();

      await expectValidationWarning(
        'Packages dependent on a pre-release',
        environment: {'_PUB_TEST_SDK_VERSION': '1.8.0'},
      );
    });
    test(
        'with a single-version dependency and it should suggest a '
        'constraint based on the version', () async {
      (await servePackages()).serve('foo', '1.2.3');
      await d.dir(appPath, [
        d.libPubspec('test_pkg', '1.0.0', deps: {'foo': '1.2.3'})
      ]).create();

      await expectValidationWarning('  foo: ^1.2.3');
    });

    group('has a dependency without a lower bound', () {
      test(
          'and it should suggest a constraint based on the locked '
          'version', () async {
        (await servePackages()).serve('foo', '1.2.3');

        await d.dir(appPath, [
          d.libPubspec('test_pkg', '1.0.0', deps: {'foo': '<3.0.0'}),
          d.file(
            'pubspec.lock',
          )
        ]).create();

        await expectValidationWarning('  foo: ">=1.2.3 <3.0.0"');
      });

      test('and it should preserve the upper-bound operator', () async {
        (await servePackages()).serve('foo', '1.2.3');
        await d.dir(appPath, [
          d.libPubspec('test_pkg', '1.0.0', deps: {'foo': '<=3.0.0'}),
          d.file(
            'pubspec.lock',
            jsonEncode({
              'packages': {
                'foo': {
                  'version': '1.2.3',
                  'source': 'hosted',
                  'description': {'name': 'foo', 'url': 'https://pub.dev'}
                }
              }
            }),
          )
        ]).create();

        await expectValidationWarning('  foo: ">=1.2.3 <=3.0.0"');
      });

      test(
          'and it should expand the suggested constraint if the '
          'locked version matches the upper bound', () async {
        (await servePackages()).serve('foo', '1.2.3');

        await d.dir(appPath, [
          d.libPubspec('test_pkg', '1.0.0', deps: {'foo': '<=1.2.3'}),
          d.file(
            'pubspec.lock',
            jsonEncode({
              'packages': {
                'foo': {
                  'version': '1.2.3',
                  'source': 'hosted',
                  'description': {'name': 'foo', 'url': 'https://pub.dev'}
                }
              }
            }),
          )
        ]).create();

        await expectValidationWarning('  foo: ^1.2.3');
      });
    });

    group('with a dependency without an upper bound', () {
      test('and it should suggest a constraint based on the lower bound',
          () async {
        (await servePackages()).serve('foo', '1.2.3');
        await d.dir(appPath, [
          d.libPubspec('test_pkg', '1.0.0', deps: {'foo': '>=1.2.3'})
        ]).create();

        await expectValidationWarning('  foo: ^1.2.3');
      });

      test('and it should preserve the lower-bound operator', () async {
        (await servePackages()).serve('foo', '1.2.4');
        await d.dir(appPath, [
          d.libPubspec('test_pkg', '1.0.0', deps: {'foo': '>1.2.3'})
        ]).create();

        await expectValidationWarning('  foo: ">1.2.3 <2.0.0"');
      });
    });

    group('has a ^ dependency', () {
      test('with a too-broad SDK constraint', () async {
        (await servePackages()).serve('foo', '1.2.3', sdk: '^1.4.0');
        await d.dir(appPath, [
          d.libPubspec(
            'test_pkg',
            '1.0.0',
            deps: {'foo': '^1.2.3'},
            sdk: '>=1.5.0 <2.0.0',
          )
        ]).create();

        await expectValidationError(
          '  sdk: "^1.8.0"',
          environment: {'_PUB_TEST_SDK_VERSION': '1.5.0'},
        );
      });
    });

    group('has a git path dependency', () {
      test('without an SDK constraint', () async {
        // Ensure we don't report anything from the real pub.dev.
        await setUpDependency({});
        await d.git('foo', [
          d.dir('subdir', [
            d.libPubspec('foo', '1.0.0', extras: {'dependencies': {}})
          ]),
        ]).create();
        await d.dir(appPath, [
          d.libPubspec(
            'integration_pkg',
            '1.0.0',
            deps: {
              'foo': {
                'git': {'url': d.path('foo'), 'path': 'subdir'}
              },
            },
            sdk: '>=1.0.0 <4.0.0',
          )
        ]).create();

        await expectValidation(
          error: allOf(
            contains('  sdk: "^2.0.0"'),
            contains('  foo: any'),
          ),
          exitCode: DATA,
        );
      });

      test('with a too-broad SDK constraint', () async {
        // Ensure we don't report anything from the real pub.dev.
        await setUpDependency({});
        await d.git('foo', [
          d.dir(
            'subdir',
            [d.libPubspec('foo', '1.0.0', sdk: '>=0.0.0 <3.0.0')],
          ),
        ]).create();
        await d.dir(appPath, [
          d.libPubspec(
            'integration_pkg',
            '1.0.0',
            deps: {
              'foo': {
                'git': {'url': d.path('foo'), 'path': 'subdir'}
              }
            },
            sdk: '>=1.24.0 <3.0.0',
          )
        ]).create();

        await expectValidation(
          error: allOf([
            contains('  sdk: "^2.0.0"'),
            contains('  foo: any'),
          ]),
          environment: {'_PUB_TEST_SDK_VERSION': '1.24.0'},
          exitCode: DATA,
        );
      });
    });

    test('depends on Flutter from a non-SDK source', () async {
      (await servePackages()).serve('flutter', '1.5.0');
      await d.dir(appPath, [
        d.libPubspec('test_pkg', '1.0.0', deps: {'flutter': '>=1.2.3 <2.0.0'})
      ]).create();

      await expectValidationError('sdk: >=1.2.3 <2.0.0');
    });

    test('depends on a Flutter package with a too-broad SDK constraint',
        () async {
      await d.dir('flutter', [d.file('version', '1.2.3')]).create();
      await flutterPackage('foo', sdk: 'any').create();
      await package(
        deps: {
          'foo': {'sdk': 'flutter', 'version': '>=1.2.3 <2.0.0'}
        },
        sdk: '>=1.18.0 <2.0.0',
      ).create();

      await expectValidationError(
        'sdk: "^1.19.0"',
        environment: {
          '_PUB_TEST_SDK_VERSION': '1.19.0',
          'FLUTTER_ROOT': path.join(d.sandbox, 'flutter'),
        },
      );
    });

    test('depends on a Flutter package with no SDK constraint', () async {
      await d.dir('flutter', [d.file('version', '1.2.3')]).create();
      await flutterPackage('foo', sdk: '>=0.0.0 <1.0.0').create();
      await package(
        sdk: '>=0.0.0 <=0.0.1',
        deps: {
          'foo': {'sdk': 'flutter', 'version': '>=1.2.3 <2.0.0'}
        },
      ).create();

      await expectValidationError(
        'sdk: "^1.19.0"',
        environment: {
          '_PUB_TEST_SDK_VERSION': '0.0.0',
          'FLUTTER_ROOT': path.join(d.sandbox, 'flutter'),
        },
      );
    });

    test('depends on a Fuchsia package with a too-broad SDK constraint',
        () async {
      await fuschiaPackage('foo', sdk: '>=0.0.0 <3.0.0').create();

      await package(
        sdk: '>=2.0.0-dev.50.0 <2.0.2',
        deps: {
          'foo': {'sdk': 'fuchsia', 'version': '>=1.2.3 <2.0.0'}
        },
      ).create();

      await expectValidationError(
        'sdk: ">=2.0.0 <2.0.2"',
        environment: {
          'FUCHSIA_DART_SDK_ROOT': path.join(d.sandbox, 'fuchsia'),
          '_PUB_TEST_SDK_VERSION': '2.0.1-dev.51.0',
        },
      );
    });
  });
}

d.Descriptor fuschiaPackage(
  String name, {
  Map<String, String> deps = const {},
  String? sdk,
}) {
  return d.dir('fuchsia', [
    d.dir('packages', [
      d.dir(name, [
        d.libDir(name, 'f(x) => 2 * x;'),
        d.libPubspec(name, '1.5.0', deps: deps, sdk: sdk),
      ]),
    ]),
  ]);
}

d.Descriptor flutterPackage(
  String name, {
  Map<String, String> deps = const {},
  String? sdk,
}) {
  return d.dir('flutter', [
    d.dir('packages', [
      d.dir(name, [
        d.libDir(name, 'f(x) => 2 * x;'),
        d.libPubspec(name, '1.5.0', deps: deps, sdk: sdk),
      ]),
    ]),
  ]);
}
