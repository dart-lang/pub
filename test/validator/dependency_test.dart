// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import 'package:pub/src/entrypoint.dart';
import 'package:pub/src/validator.dart';
import 'package:pub/src/validator/dependency.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

Validator dependency(Entrypoint entrypoint) =>
    new DependencyValidator(entrypoint);

expectDependencyValidationError(String error) {
  expect(validatePackage(dependency),
      completion(pairOf(anyElement(contains(error)), isEmpty)));
}

expectDependencyValidationWarning(String warning) {
  expect(validatePackage(dependency),
      completion(pairOf(isEmpty, anyElement(contains(warning)))));
}

/// Sets up a test package with dependency [dep] and mocks a server with
/// [hostedVersions] of the package available.
Future setUpDependency(Map dep, {List<String> hostedVersions}) {
  useMockClient(new MockClient((request) {
    expect(request.method, equals("GET"));
    expect(request.url.path, equals("/api/packages/foo"));

    if (hostedVersions == null) {
      return new Future.value(new http.Response("not found", 404));
    } else {
      return new Future.value(new http.Response(
          JSON.encode({
            "name": "foo",
            "uploaders": ["nweiz@google.com"],
            "versions": hostedVersions
                .map((version) =>
                    packageVersionApiMap(packageMap('foo', version)))
                .toList()
          }),
          200));
    }
  }));

  return d.dir(appPath, [
    d.libPubspec("test_pkg", "1.0.0", deps: {"foo": dep})
  ]).create();
}

main() {
  group('should consider a package valid if it', () {
    test('looks normal', () async {
      await d.validPackage.create();
      expectNoValidationError(dependency);
    });

    test('has a ^ constraint with an appropriate SDK constraint', () async {
      await d.dir(appPath, [
        d.libPubspec("test_pkg", "1.0.0",
            deps: {"foo": "^1.2.3"}, sdk: ">=1.8.0 <2.0.0")
      ]).create();
      expectNoValidationError(dependency);
    });

    test('depends on Flutter from an SDK source', () async {
      await d.dir(appPath, [
        d.libPubspec("test_pkg", "1.0.0", deps: {
          "flutter": {"sdk": ">=1.2.3 <2.0.0"}
        })
      ]).create();

      expectNoValidationError(dependency);
    });
  });

  group('should consider a package invalid if it', () {
    setUp(d.validPackage.create);

    group('has a git dependency', () {
      group('where a hosted version exists', () {
        test("and should suggest the hosted primary version", () async {
          await setUpDependency({'git': 'git://github.com/dart-lang/foo'},
              hostedVersions: ["3.0.0-pre", "2.0.0", "1.0.0"]);
          expectDependencyValidationWarning('  foo: ">=2.0.0 <3.0.0"');
        });

        test(
            "and should suggest the hosted prerelease version if "
            "it's the only version available", () async {
          await setUpDependency({'git': 'git://github.com/dart-lang/foo'},
              hostedVersions: ["3.0.0-pre", "2.0.0-pre"]);
          expectDependencyValidationWarning('  foo: ">=3.0.0-pre <4.0.0"');
        });

        test(
            "and should suggest a tighter constraint if primary is "
            "pre-1.0.0", () async {
          await setUpDependency({'git': 'git://github.com/dart-lang/foo'},
              hostedVersions: ["0.0.1", "0.0.2"]);
          expectDependencyValidationWarning('  foo: ">=0.0.2 <0.1.0"');
        });
      });

      group('where no hosted version exists', () {
        test("and should use the other source's version", () async {
          await setUpDependency({
            'git': 'git://github.com/dart-lang/foo',
            'version': '>=1.0.0 <2.0.0'
          });
          expectDependencyValidationWarning('  foo: ">=1.0.0 <2.0.0"');
        });

        test(
            "and should use the other source's unquoted version if "
            "concrete", () async {
          await setUpDependency(
              {'git': 'git://github.com/dart-lang/foo', 'version': '0.2.3'});
          expectDependencyValidationWarning('  foo: 0.2.3');
        });
      });
    });

    group('has a path dependency', () {
      group('where a hosted version exists', () {
        test("and should suggest the hosted primary version", () async {
          await setUpDependency({'path': path.join(d.sandbox, 'foo')},
              hostedVersions: ["3.0.0-pre", "2.0.0", "1.0.0"]);
          expectDependencyValidationError('  foo: ">=2.0.0 <3.0.0"');
        });

        test(
            "and should suggest the hosted prerelease version if "
            "it's the only version available", () async {
          await setUpDependency({'path': path.join(d.sandbox, 'foo')},
              hostedVersions: ["3.0.0-pre", "2.0.0-pre"]);
          expectDependencyValidationError('  foo: ">=3.0.0-pre <4.0.0"');
        });

        test(
            "and should suggest a tighter constraint if primary is "
            "pre-1.0.0", () async {
          await setUpDependency({'path': path.join(d.sandbox, 'foo')},
              hostedVersions: ["0.0.1", "0.0.2"]);
          expectDependencyValidationError('  foo: ">=0.0.2 <0.1.0"');
        });
      });

      group('where no hosted version exists', () {
        test("and should use the other source's version", () async {
          await setUpDependency({
            'path': path.join(d.sandbox, 'foo'),
            'version': '>=1.0.0 <2.0.0'
          });
          expectDependencyValidationError('  foo: ">=1.0.0 <2.0.0"');
        });

        test(
            "and should use the other source's unquoted version if "
            "concrete", () async {
          await setUpDependency(
              {'path': path.join(d.sandbox, 'foo'), 'version': '0.2.3'});
          expectDependencyValidationError('  foo: 0.2.3');
        });
      });
    });

    group('has an unconstrained dependency', () {
      group('and it should not suggest a version', () {
        test("if there's no lockfile", () async {
          await d.dir(appPath, [
            d.libPubspec("test_pkg", "1.0.0", deps: {"foo": "any"})
          ]).create();

          expect(
              validatePackage(dependency),
              completion(
                  pairOf(isEmpty, everyElement(isNot(contains("\n  foo:"))))));
        });

        test(
            "if the lockfile doesn't have an entry for the "
            "dependency", () async {
          await d.dir(appPath, [
            d.libPubspec("test_pkg", "1.0.0", deps: {"foo": "any"}),
            d.file(
                "pubspec.lock",
                JSON.encode({
                  'packages': {
                    'bar': {
                      'version': '1.2.3',
                      'source': 'hosted',
                      'description': {
                        'name': 'bar',
                        'url': 'http://pub.dartlang.org'
                      }
                    }
                  }
                }))
          ]).create();

          expect(
              validatePackage(dependency),
              completion(
                  pairOf(isEmpty, everyElement(isNot(contains("\n  foo:"))))));
        });
      });

      group('with a lockfile', () {
        test(
            'and it should suggest a constraint based on the locked '
            'version', () async {
          await d.dir(appPath, [
            d.libPubspec("test_pkg", "1.0.0", deps: {"foo": "any"}),
            d.file(
                "pubspec.lock",
                JSON.encode({
                  'packages': {
                    'foo': {
                      'version': '1.2.3',
                      'source': 'hosted',
                      'description': {
                        'name': 'foo',
                        'url': 'http://pub.dartlang.org'
                      }
                    }
                  }
                }))
          ]).create();

          expectDependencyValidationWarning('  foo: ">=1.2.3 <2.0.0"');
        });

        test(
            'and it should suggest a concrete constraint if the locked '
            'version is pre-1.0.0', () async {
          await d.dir(appPath, [
            d.libPubspec("test_pkg", "1.0.0", deps: {"foo": "any"}),
            d.file(
                "pubspec.lock",
                JSON.encode({
                  'packages': {
                    'foo': {
                      'version': '0.1.2',
                      'source': 'hosted',
                      'description': {
                        'name': 'foo',
                        'url': 'http://pub.dartlang.org'
                      }
                    }
                  }
                }))
          ]).create();

          expectDependencyValidationWarning('  foo: ">=0.1.2 <0.2.0"');
        });
      });
    });

    test(
        'with a single-version dependency and it should suggest a '
        'constraint based on the version', () async {
      await d.dir(appPath, [
        d.libPubspec("test_pkg", "1.0.0", deps: {"foo": "1.2.3"})
      ]).create();

      expectDependencyValidationWarning('  foo: ">=1.2.3 <2.0.0"');
    });

    group('has a dependency without a lower bound', () {
      group('and it should not suggest a version', () {
        test("if there's no lockfile", () async {
          await d.dir(appPath, [
            d.libPubspec("test_pkg", "1.0.0", deps: {"foo": "<3.0.0"})
          ]).create();

          expect(
              validatePackage(dependency),
              completion(
                  pairOf(isEmpty, everyElement(isNot(contains("\n  foo:"))))));
        });

        test(
            "if the lockfile doesn't have an entry for the "
            "dependency", () async {
          await d.dir(appPath, [
            d.libPubspec("test_pkg", "1.0.0", deps: {"foo": "<3.0.0"}),
            d.file(
                "pubspec.lock",
                JSON.encode({
                  'packages': {
                    'bar': {
                      'version': '1.2.3',
                      'source': 'hosted',
                      'description': {
                        'name': 'bar',
                        'url': 'http://pub.dartlang.org'
                      }
                    }
                  }
                }))
          ]).create();

          expect(
              validatePackage(dependency),
              completion(
                  pairOf(isEmpty, everyElement(isNot(contains("\n  foo:"))))));
        });
      });

      group('with a lockfile', () {
        test(
            'and it should suggest a constraint based on the locked '
            'version', () async {
          await d.dir(appPath, [
            d.libPubspec("test_pkg", "1.0.0", deps: {"foo": "<3.0.0"}),
            d.file(
                "pubspec.lock",
                JSON.encode({
                  'packages': {
                    'foo': {
                      'version': '1.2.3',
                      'source': 'hosted',
                      'description': {
                        'name': 'foo',
                        'url': 'http://pub.dartlang.org'
                      }
                    }
                  }
                }))
          ]).create();

          expectDependencyValidationWarning('  foo: ">=1.2.3 <3.0.0"');
        });

        test('and it should preserve the upper-bound operator', () async {
          await d.dir(appPath, [
            d.libPubspec("test_pkg", "1.0.0", deps: {"foo": "<=3.0.0"}),
            d.file(
                "pubspec.lock",
                JSON.encode({
                  'packages': {
                    'foo': {
                      'version': '1.2.3',
                      'source': 'hosted',
                      'description': {
                        'name': 'foo',
                        'url': 'http://pub.dartlang.org'
                      }
                    }
                  }
                }))
          ]).create();

          expectDependencyValidationWarning('  foo: ">=1.2.3 <=3.0.0"');
        });

        test(
            'and it should expand the suggested constraint if the '
            'locked version matches the upper bound', () async {
          await d.dir(appPath, [
            d.libPubspec("test_pkg", "1.0.0", deps: {"foo": "<=1.2.3"}),
            d.file(
                "pubspec.lock",
                JSON.encode({
                  'packages': {
                    'foo': {
                      'version': '1.2.3',
                      'source': 'hosted',
                      'description': {
                        'name': 'foo',
                        'url': 'http://pub.dartlang.org'
                      }
                    }
                  }
                }))
          ]).create();

          expectDependencyValidationWarning('  foo: ">=1.2.3 <2.0.0"');
        });
      });
    });

    group('with a dependency without an upper bound', () {
      test('and it should suggest a constraint based on the lower bound',
          () async {
        await d.dir(appPath, [
          d.libPubspec("test_pkg", "1.0.0", deps: {"foo": ">=1.2.3"})
        ]).create();

        expectDependencyValidationWarning('  foo: ">=1.2.3 <2.0.0"');
      });

      test('and it should preserve the lower-bound operator', () async {
        await d.dir(appPath, [
          d.libPubspec("test_pkg", "1.0.0", deps: {"foo": ">1.2.3"})
        ]).create();

        expectDependencyValidationWarning('  foo: ">1.2.3 <2.0.0"');
      });
    });

    group('has a ^ dependency', () {
      test("without an SDK constraint", () async {
        await d.dir(appPath, [
          d.libPubspec("integration_pkg", "1.0.0", deps: {"foo": "^1.2.3"})
        ]).create();

        expectDependencyValidationError('  foo: ">=1.2.3 <2.0.0"');
      });

      test("with a too-broad SDK constraint", () async {
        await d.dir(appPath, [
          d.libPubspec("test_pkg", "1.0.0",
              deps: {"foo": "^1.2.3"}, sdk: ">=1.5.0 <2.0.0")
        ]).create();

        expectDependencyValidationError('  foo: ">=1.2.3 <2.0.0"');
      });
    });

    test('depends on Flutter from a non-SDK source', () async {
      await d.dir(appPath, [
        d.libPubspec("test_pkg", "1.0.0", deps: {"flutter": ">=1.2.3 <2.0.0"})
      ]).create();

      expectDependencyValidationError('sdk: >=1.2.3 <2.0.0');
    });
  });
}
