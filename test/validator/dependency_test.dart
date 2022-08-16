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

d.DirectoryDescriptor package(
    {String version = '1.0.0', Map? deps, String? sdk}) {
  return d.dir(appPath, [
    d.libPubspec('test_pkg', version,
        sdk: sdk ?? '>=1.8.0 <=2.0.0', deps: deps),
    d.file('LICENSE', 'Eh, do what you want.'),
    d.file('README.md', "This package isn't real."),
    d.file('CHANGELOG.md', '# $version\nFirst version\n'),
    d.dir('lib', [d.file('test_pkg.dart', 'int i = 1;')])
  ]);
}

Future<void> expectValidation({error, int exitCode = 0}) async {
  await runPub(
    error: error ?? contains('Package has 0 warnings.'),
    args: ['publish', '--dry-run'],
    // workingDirectory: d.path(appPath),
    exitCode: exitCode,
  );
}

Future<void> expectValidationWarning(error) async {
  if (error is String) error = contains(error);
  await expectValidation(
      error: allOf([error, contains('Package has 1 warning.')]),
      exitCode: DATA);
}

Future<void> expectValidationError(String text) async {
  await expectValidation(
      error: allOf([
        contains(text),
        contains('Package validation found the following error:')
      ]),
      exitCode: DATA);
}

Future<void> setUpDependency(dep,
    {List<String> hostedVersions = const []}) async {
  final server = await servePackages();
  for (final version in hostedVersions) {
    server.serve('foo', version);
  }
  await package(deps: {'foo': dep}).create();
}

void main() {
  group('should consider a package valid if it', () {
    test('looks normal', () async {
      await package().create();
      await expectValidation();
    });

    test('has a ^ constraint with an appropriate SDK constraint', () async {
      await package(deps: {'foo': '^1.2.3'}).create();
      await expectValidation();
    });

    test('with a dependency on a pre-release while being one', () async {
      await package(version: '1.0.0-dev', deps: {'foo': '^1.2.3-dev'}).create();

      await expectValidation();
    });

    test('has a git path dependency with an appropriate SDK constraint',
        () async {
      await servePackages();
      await package(deps: {
        'foo': {
          'git': {'url': 'git://github.com/dart-lang/foo', 'path': 'subdir'}
        }
      }, sdk: '>=2.0.0 <3.0.0')
          .create();

      // We should get a warning for using a git dependency, but not an error.
      await expectValidationWarning('  foo: any');
    });

    test('depends on Flutter from an SDK source', () async {
      await package(deps: {
        'flutter': {'sdk': 'flutter'}
      }, sdk: '>=1.19.0 <2.0.0')
          .create();

      await expectValidation();
    });

    test(
        'depends on a package from Flutter with an appropriate Dart SDK '
        'constraint', () async {
      await package(
        deps: {
          'foo': {'sdk': 'flutter', 'version': '>=1.2.3 <2.0.0'},
        },
        sdk: '>=1.19.0 <2.0.0',
      ).create();

      await expectValidation();
    });

    test(
        'depends on a package from Fuchsia with an appropriate Dart SDK '
        'constraint', () async {
      await package(sdk: '>=2.0.0-dev.51.0 <2.0.0', deps: {
        'foo': {'sdk': 'fuchsia', 'version': '>=1.2.3 <2.0.0'}
      }).create();
      await d.validPackage.create();

      await expectValidation();
    });
  });

  group('should consider a package invalid if it', () {
    setUp(package().create);
    group('has a git dependency', () {
      group('where a hosted version exists', () {
        test('and should suggest the hosted primary version', () async {
          await setUpDependency({'git': 'git://github.com/dart-lang/foo'},
              hostedVersions: ['3.0.0-pre', '2.0.0', '1.0.0']);
          await expectValidationWarning('  foo: ^2.0.0');
        });

        test(
            'and should suggest the hosted prerelease version if '
            "it's the only version available", () async {
          await setUpDependency({'git': 'git://github.com/dart-lang/foo'},
              hostedVersions: ['3.0.0-pre', '2.0.0-pre']);
          await expectValidationWarning('  foo: ^3.0.0-pre');
        });

        test(
            'and should suggest a tighter constraint if primary is '
            'pre-1.0.0', () async {
          await setUpDependency({'git': 'git://github.com/dart-lang/foo'},
              hostedVersions: ['0.0.1', '0.0.2']);
          await expectValidationWarning('  foo: ^0.0.2');
        });
      });

      group('where no hosted version exists', () {
        test("and should use the other source's version", () async {
          await setUpDependency({
            'git': 'git://github.com/dart-lang/foo',
            'version': '>=1.0.0 <2.0.0'
          });
          await expectValidationWarning('  foo: ">=1.0.0 <2.0.0"');
        });

        test(
            "and should use the other source's unquoted version if "
            'concrete', () async {
          await setUpDependency(
              {'git': 'git://github.com/dart-lang/foo', 'version': '0.2.3'});
          await expectValidationWarning('  foo: 0.2.3');
        });
      });
    });

    group('has a path dependency', () {
      group('where a hosted version exists', () {
        test('and should suggest the hosted primary version', () async {
          await setUpDependency({'path': path.join(d.sandbox, 'foo')},
              hostedVersions: ['3.0.0-pre', '2.0.0', '1.0.0']);
          await expectValidationError('  foo: ^2.0.0');
        });

        test(
            'and should suggest the hosted prerelease version if '
            "it's the only version available", () async {
          await setUpDependency({'path': path.join(d.sandbox, 'foo')},
              hostedVersions: ['3.0.0-pre', '2.0.0-pre']);
          await expectValidationError('  foo: ^3.0.0-pre');
        });

        test(
            'and should suggest a tighter constraint if primary is '
            'pre-1.0.0', () async {
          await setUpDependency({'path': path.join(d.sandbox, 'foo')},
              hostedVersions: ['0.0.1', '0.0.2']);
          await expectValidationError('  foo: ^0.0.2');
        });
      });

      group('where no hosted version exists', () {
        test("and should use the other source's version", () async {
          await setUpDependency({
            'path': path.join(d.sandbox, 'foo'),
            'version': '>=1.0.0 <2.0.0'
          });
          await expectValidationError('  foo: ">=1.0.0 <2.0.0"');
        });

        test(
            "and should use the other source's unquoted version if "
            'concrete', () async {
          await setUpDependency(
              {'path': path.join(d.sandbox, 'foo'), 'version': '0.2.3'});
          await expectValidationError('  foo: 0.2.3');
        });
      });
    });

    group('has an unconstrained dependency', () {
      group('and it should not suggest a version', () {
        test("if there's no lockfile", () async {
          await d.dir(appPath, [
            d.libPubspec('test_pkg', '1.0.0', deps: {'foo': 'any'})
          ]).create();

          await expectValidationWarning(isNot(contains('\n  foo:')));
        });

        test("if the lockfile doesn't have an entry for the dependency",
            () async {
          await d.dir(appPath, [
            d.libPubspec('test_pkg', '1.0.0', deps: {'foo': 'any'}),
            d.file(
                'pubspec.lock',
                jsonEncode({
                  'packages': {
                    'bar': {
                      'version': '1.2.3',
                      'source': 'hosted',
                      'description': {
                        'name': 'bar',
                        'url': 'https://pub.dev'
                      }
                    }
                  }
                }))
          ]).create();

          await expectValidationWarning(isNot(contains('\n  foo:')));
        });
      });

      group('with a lockfile', () {
        test(
            'and it should suggest a constraint based on the locked '
            'version', () async {
          await d.dir(appPath, [
            d.libPubspec('test_pkg', '1.0.0', deps: {'foo': 'any'}),
            d.file(
                'pubspec.lock',
                jsonEncode({
                  'packages': {
                    'foo': {
                      'version': '1.2.3',
                      'source': 'hosted',
                      'description': {
                        'name': 'foo',
                        'url': 'https://pub.dev'
                      }
                    }
                  }
                }))
          ]).create();

          await expectValidationWarning('  foo: ^1.2.3');
        });

        test(
            'and it should suggest a concrete constraint if the locked '
            'version is pre-1.0.0', () async {
          await d.dir(appPath, [
            d.libPubspec('test_pkg', '1.0.0', deps: {'foo': 'any'}),
            d.file(
                'pubspec.lock',
                jsonEncode({
                  'packages': {
                    'foo': {
                      'version': '0.1.2',
                      'source': 'hosted',
                      'description': {
                        'name': 'foo',
                        'url': 'https://pub.dev'
                      }
                    }
                  }
                }))
          ]).create();

          await expectValidationWarning('  foo: ^0.1.2');
        });
      });
    });

    test('with a dependency on a pre-release without being one', () async {
      await d.dir(appPath, [
        d.libPubspec(
          'test_pkg',
          '1.0.0',
          deps: {'foo': '^1.2.3-dev'},
          sdk: '>=1.19.0 <2.0.0',
        )
      ]).create();

      await expectValidationWarning('Packages dependent on a pre-release');
    });
    test(
        'with a single-version dependency and it should suggest a '
        'constraint based on the version', () async {
      await d.dir(appPath, [
        d.libPubspec('test_pkg', '1.0.0', deps: {'foo': '1.2.3'})
      ]).create();

      await expectValidationWarning('  foo: ^1.2.3');
    });

    group('has a dependency without a lower bound', () {
      group('and it should not suggest a version', () {
        test("if there's no lockfile", () async {
          await d.dir(appPath, [
            d.libPubspec('test_pkg', '1.0.0', deps: {'foo': '<3.0.0'})
          ]).create();

          await expectValidationWarning(isNot(contains('\n  foo:')));
        });

        test(
            "if the lockfile doesn't have an entry for the "
            'dependency', () async {
          await d.dir(appPath, [
            d.libPubspec('test_pkg', '1.0.0', deps: {'foo': '<3.0.0'}),
            d.file(
                'pubspec.lock',
                jsonEncode({
                  'packages': {
                    'bar': {
                      'version': '1.2.3',
                      'source': 'hosted',
                      'description': {
                        'name': 'bar',
                        'url': 'https://pub.dev'
                      }
                    }
                  }
                }))
          ]).create();

          await expectValidationWarning(isNot(contains('\n  foo:')));
        });
      });

      group('with a lockfile', () {
        test(
            'and it should suggest a constraint based on the locked '
            'version', () async {
          await d.dir(appPath, [
            d.libPubspec('test_pkg', '1.0.0', deps: {'foo': '<3.0.0'}),
            d.file(
                'pubspec.lock',
                jsonEncode({
                  'packages': {
                    'foo': {
                      'version': '1.2.3',
                      'source': 'hosted',
                      'description': {
                        'name': 'foo',
                        'url': 'https://pub.dev'
                      }
                    }
                  }
                }))
          ]).create();

          await expectValidationWarning('  foo: ">=1.2.3 <3.0.0"');
        });

        test('and it should preserve the upper-bound operator', () async {
          await d.dir(appPath, [
            d.libPubspec('test_pkg', '1.0.0', deps: {'foo': '<=3.0.0'}),
            d.file(
                'pubspec.lock',
                jsonEncode({
                  'packages': {
                    'foo': {
                      'version': '1.2.3',
                      'source': 'hosted',
                      'description': {
                        'name': 'foo',
                        'url': 'https://pub.dev'
                      }
                    }
                  }
                }))
          ]).create();

          await expectValidationWarning('  foo: ">=1.2.3 <=3.0.0"');
        });

        test(
            'and it should expand the suggested constraint if the '
            'locked version matches the upper bound', () async {
          await d.dir(appPath, [
            d.libPubspec('test_pkg', '1.0.0', deps: {'foo': '<=1.2.3'}),
            d.file(
                'pubspec.lock',
                jsonEncode({
                  'packages': {
                    'foo': {
                      'version': '1.2.3',
                      'source': 'hosted',
                      'description': {
                        'name': 'foo',
                        'url': 'https://pub.dev'
                      }
                    }
                  }
                }))
          ]).create();

          await expectValidationWarning('  foo: ^1.2.3');
        });
      });
    });

    group('with a dependency without an upper bound', () {
      test('and it should suggest a constraint based on the lower bound',
          () async {
        await d.dir(appPath, [
          d.libPubspec('test_pkg', '1.0.0', deps: {'foo': '>=1.2.3'})
        ]).create();

        await expectValidationWarning('  foo: ^1.2.3');
      });

      test('and it should preserve the lower-bound operator', () async {
        await d.dir(appPath, [
          d.libPubspec('test_pkg', '1.0.0', deps: {'foo': '>1.2.3'})
        ]).create();

        await expectValidationWarning('  foo: ">1.2.3 <2.0.0"');
      });
    });

    group('has a ^ dependency', () {
      test('without an SDK constraint', () async {
        await d.dir(appPath, [
          d.libPubspec('integration_pkg', '1.0.0', deps: {'foo': '^1.2.3'})
        ]).create();

        await expectValidationError('  sdk: ">=1.8.0 <2.0.0"');
      });

      test('with a too-broad SDK constraint', () async {
        await d.dir(appPath, [
          d.libPubspec('test_pkg', '1.0.0',
              deps: {'foo': '^1.2.3'}, sdk: '>=1.5.0 <2.0.0')
        ]).create();

        await expectValidationError('  sdk: ">=1.8.0 <2.0.0"');
      });
    });

    group('has a git path dependency', () {
      test('without an SDK constraint', () async {
        // Ensure we don't report anything from the real pub.dev.
        await setUpDependency({});
        await d.dir(appPath, [
          d.libPubspec('integration_pkg', '1.0.0', deps: {
            'foo': {
              'git': {'url': 'git://github.com/dart-lang/foo', 'path': 'subdir'}
            }
          })
        ]).create();

        await expectValidation(
          error: allOf(
              contains('  sdk: ">=2.0.0 <3.0.0"'), contains('  foo: any')),
          exitCode: DATA,
        );
      });

      test('with a too-broad SDK constraint', () async {
        // Ensure we don't report anything from the real pub.dev.
        await setUpDependency({});
        await d.dir(appPath, [
          d.libPubspec('integration_pkg', '1.0.0',
              deps: {
                'foo': {
                  'git': {
                    'url': 'git://github.com/dart-lang/foo',
                    'path': 'subdir'
                  }
                }
              },
              sdk: '>=1.24.0 <3.0.0')
        ]).create();

        await expectValidation(
          error: allOf([
            contains('  sdk: ">=2.0.0 <3.0.0"'),
            contains('  foo: any'),
          ]),
          exitCode: DATA,
        );
      });
    });

    test('depends on Flutter from a non-SDK source', () async {
      await d.dir(appPath, [
        d.libPubspec('test_pkg', '1.0.0', deps: {'flutter': '>=1.2.3 <2.0.0'})
      ]).create();

      await expectValidationError('sdk: >=1.2.3 <2.0.0');
    });

    test('depends on a Flutter package from an unknown SDK', () async {
      await package(deps: {
        'foo': {'sdk': 'fblthp', 'version': '>=1.2.3 <2.0.0'}
      }).create();

      await expectValidationError('Unknown SDK "fblthp" for dependency "foo".');
    });

    test('depends on a Flutter package with a too-broad SDK constraint',
        () async {
      await package(
        deps: {
          'foo': {'sdk': 'flutter', 'version': '>=1.2.3 <2.0.0'}
        },
        sdk: '>=1.18.0 <2.0.0',
      ).create();

      await expectValidationError('sdk: ">=1.19.0 <2.0.0"');
    });

    test('depends on a Flutter package with no SDK constraint', () async {
      await package(sdk: '>=0.0.0 <=0.0.1', deps: {
        'foo': {'sdk': 'flutter', 'version': '>=1.2.3 <2.0.0'}
      }).create();

      await expectValidationError('sdk: ">=1.19.0 <2.0.0"');
    });

    test('depends on a Fuchsia package with a too-broad SDK constraint',
        () async {
      await package(
        sdk: '>=2.0.0-dev.50.0 <2.0.0',
        deps: {
          'foo': {'sdk': 'fuchsia', 'version': '>=1.2.3 <2.0.0'}
        },
      ).create();

      await expectValidationError('sdk: ">=2.0.0 <3.0.0"');
    });

    test('depends on a Fuchsia package with no SDK constraint', () async {
      await package(sdk: '>=0.0.0 <1.0.0', deps: {
        'foo': {'sdk': 'fuchsia', 'version': '>=1.2.3 <2.0.0'}
      }).create();

      await expectValidationError('sdk: ">=2.0.0 <3.0.0"');
    });
  });
}
