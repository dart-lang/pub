// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// TODO(sigurdm): This should ideally be a separate _test.dart file, however to
// share the compiled snapshot for the embedded test-runner this is included by
// embedding_test.dart

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub/src/io.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'embedding_test.dart';

late PackageServer server;

void testEnsurePubspecResolved() {
  group('ensurePubspecResolved', () {
    setUp(() async {
      server = await servePackages();

      server.serve('foo', '1.0.0');
      server.serve('foo', '2.0.0');

      await d.dir(appPath, [
        d.appPubspec(),
        d.dir('web', []),
        d.dir('bin', [d.file('script.dart', "main() => print('hello!');")]),
      ]).create();

      await pubGet();
    });

    group('Does an implicit pub get if', () {
      test("there's no lockfile", () async {
        File(p.join(d.sandbox, 'myapp/pubspec.lock')).deleteSync();
        await _implicitPubGet('No pubspec.lock file found');
      });

      test("there's no package_config.json", () async {
        File(
          p.join(d.sandbox, 'myapp/.dart_tool/package_config.json'),
        ).deleteSync();

        await _implicitPubGet(
          '`./pubspec.yaml` exists without corresponding `./pubspec.yaml` or `.dart_tool/pub/workspace_ref.json`.',
        );
      });

      test('the pubspec has a new dependency', () async {
        await d.dir('foo', [d.libPubspec('foo', '1.0.0')]).create();

        await d.dir(appPath, [
          d.appPubspec(
            dependencies: {
              'foo': {'path': '../foo'},
            },
          ),
        ]).create();

        // Ensure that the pubspec looks newer than the lockfile.
        await _touch('pubspec.yaml');

        await _implicitPubGet(
          'The pubspec.yaml file has changed since the '
          'pubspec.lock file was generated',
        );
      });

      test('the lockfile has a dependency from the wrong source', () async {
        await d.dir(appPath, [
          d.appPubspec(dependencies: {'foo': '1.0.0'}),
        ]).create();

        await pubGet();

        await createLockFile(appPath, dependenciesInSandBox: ['foo']);

        // Ensure that the pubspec looks newer than the lockfile.
        await _touch('pubspec.yaml');

        await _implicitPubGet(
          'The pubspec.yaml file has changed since the '
          'pubspec.lock file was generated',
        );
      });

      test('the lockfile has a dependency from an unknown source', () async {
        await d.dir(appPath, [
          d.appPubspec(dependencies: {'foo': '1.0.0'}),
        ]).create();

        await pubGet();

        await d.dir(appPath, [
          d.file(
            'pubspec.lock',
            yaml({
              'packages': {
                'foo': {
                  'description': 'foo',
                  'version': '1.0.0',
                  'source': 'sdk',
                },
              },
            }),
          ),
        ]).create();

        // Ensure that the pubspec looks newer than the lockfile.
        await _touch('pubspec.yaml');

        await _implicitPubGet(
          'The pubspec.yaml file has changed since the '
          'pubspec.lock file was generated.',
        );
      });

      test(
        'the lockfile has a dependency with the wrong description',
        () async {
          await d.dir('bar', [d.libPubspec('foo', '1.0.0')]).create();

          await d.dir(appPath, [
            d.appPubspec(
              dependencies: {
                'foo': {'path': '../bar'},
              },
            ),
          ]).create();

          await pubGet();

          await createLockFile(appPath, dependenciesInSandBox: ['foo']);

          // Ensure that the pubspec looks newer than the lockfile.
          await _touch('pubspec.yaml');

          await _implicitPubGet(
            'The pubspec.yaml file has changed since the '
            'pubspec.lock file was generated',
          );
        },
      );

      test('the pubspec has an incompatible version of a dependency', () async {
        await d.dir(appPath, [
          d.appPubspec(dependencies: {'foo': '1.0.0'}),
        ]).create();

        await pubGet();

        await d.dir(appPath, [
          d.appPubspec(dependencies: {'foo': '2.0.0'}),
        ]).create();

        // Ensure that the pubspec looks newer than the lockfile.
        await _touch('pubspec.yaml');

        await _implicitPubGet(
          'The pubspec.yaml file has changed since the '
          'pubspec.lock file was generated',
        );
      });

      test('the lockfile is pointing to an unavailable package with a newer '
          'pubspec', () async {
        await d.dir(appPath, [
          d.appPubspec(dependencies: {'foo': '1.0.0'}),
        ]).create();

        await pubGet();

        deleteEntry(p.join(d.sandbox, cachePath));

        // Ensure that the pubspec looks newer than the lockfile.
        await _touch('pubspec.yaml');

        await _implicitPubGet('`pubspec.yaml` is newer than `pubspec.lock`');
      });

      test('the package_config.json file points to the wrong place', () async {
        await d.dir('bar', [d.libPubspec('foo', '1.0.0')]).create();

        await d.dir(appPath, [
          d.appPubspec(
            dependencies: {
              'foo': {'path': '../bar'},
            },
          ),
        ]).create();

        await pubGet();

        await d.dir(appPath, [
          d.packageConfigFile([
            d.packageConfigEntry(
              name: 'foo',
              path: '../foo', // this is the wrong path
            ),
            d.packageConfigEntry(name: 'myapp', path: '.'),
          ]),
        ]).create();

        // Ensure that the pubspec looks newer than the lockfile.
        await _touch('pubspec.lock');

        await _implicitPubGet('Could not find `../foo/pubspec.yaml`');
      });

      test(
        "the lock file's SDK constraint doesn't match the current SDK",
        () async {
          // Avoid using a path dependency because it triggers the full
          // validation logic. We want to be sure SDK-validation works without
          // that logic.
          server.serve(
            'foo',
            '1.0.0',
            pubspec: {
              'environment': {'sdk': '>=3.0.0 <3.1.0'},
            },
          );

          await d.dir(appPath, [
            d.pubspec({
              'name': 'myapp',
              'environment': {'sdk': '^3.0.0'},
              'dependencies': {'foo': '^1.0.0'},
            }),
          ]).create();

          await pubGet(environment: {'_PUB_TEST_SDK_VERSION': '3.0.0'});

          server.serve(
            'foo',
            '1.0.1',
            pubspec: {
              'environment': {'sdk': '^3.0.0'},
            },
          );

          await _implicitPubGet(
            'The Dart SDK was updated since last package resolution.',
          );
        },
      );

      test("the lock file's Flutter SDK constraint doesn't match the "
          'current Flutter SDK', () async {
        // Avoid using a path dependency because it triggers the full validation
        // logic. We want to be sure SDK-validation works without that logic.
        server.serve(
          'foo',
          '3.0.0',
          pubspec: {
            'environment': {
              'flutter': '>=1.0.0 <2.0.0',
              'sdk': defaultSdkConstraint,
            },
          },
        );

        await d.dir('flutter', [d.flutterVersion('1.2.3')]).create();

        await d.dir(appPath, [
          d.appPubspec(dependencies: {'foo': '^3.0.0'}),
        ]).create();

        await pubGet(
          environment: {'FLUTTER_ROOT': p.join(d.sandbox, 'flutter')},
        );
        await _noImplicitPubGet(
          environment: {'FLUTTER_ROOT': p.join(d.sandbox, 'flutter')},
        );
        await d.dir('flutter', [d.flutterVersion('0.9.0')]).create();

        server.serve(
          'foo',
          '3.0.1',
          pubspec: {
            'environment': {
              'flutter': '>=0.1.0 <2.0.0',
              'sdk': defaultSdkConstraint,
            },
          },
        );

        await _implicitPubGet(
          'Flutter has updated since last invocation.',
          environment: {'FLUTTER_ROOT': p.join(d.sandbox, 'flutter')},
        );
      });

      test(
        "a path dependency's dependency doesn't match the lockfile",
        () async {
          await d.dir('bar', [
            d.libPubspec('bar', '1.0.0', deps: {'foo': '1.0.0'}),
          ]).create();

          await d.dir(appPath, [
            d.appPubspec(
              dependencies: {
                'bar': {'path': '../bar'},
              },
            ),
          ]).create();

          await pubGet();

          // Update bar's pubspec without touching the app's.
          await d.dir('bar', [
            d.libPubspec('bar', '1.0.0', deps: {'foo': '2.0.0'}),
          ]).create();

          // To ensure the timestamp is strictly later we need to touch again
          // here.
          await _touch(p.join(d.sandbox, 'bar', 'pubspec.yaml'));

          await _implicitPubGet(
            '../bar/pubspec.yaml has changed '
            'since the pubspec.lock file was generated.',
          );
        },
      );

      test("a path dependency's language version "
          "doesn't match the package_config.json", () async {
        await d.dir('bar', [
          d.libPubspec(
            'bar',
            '1.0.0',
            deps: {'foo': '1.0.0'},
            // Creates language version requirement 2.99
            sdk: '>= 2.99.0 <=4.0.0', // tests runs with '3.1.2+3'
          ),
        ]).create();

        await d.dir(appPath, [
          d.appPubspec(
            dependencies: {
              'bar': {'path': '../bar'},
            },
          ),
        ]).create();

        await pubGet();

        // Update bar's pubspec without touching the app's.
        await d.dir('bar', [
          d.libPubspec(
            'bar',
            '1.0.0',
            deps: {'foo': '1.0.0'},
            // Creates language version requirement 2.100
            sdk: '>= 2.100.0 <=4.0.0', // tests runs with '3.1.2+3'
          ),
        ]).create();
        // To ensure the timestamp is strictly later we need to touch again
        // here.
        await _touch(p.join(d.sandbox, 'bar', 'pubspec.yaml'));

        await _implicitPubGet(
          '../bar/pubspec.yaml has changed '
          'since the pubspec.lock file was generated.',
        );
      });
    });

    group("doesn't require the user to run pub get first if", () {
      test('the pubspec is older than the lockfile which is older than the '
          'package-config, even if the contents are wrong', () async {
        await d.dir(appPath, [
          d.appPubspec(dependencies: {'foo': '1.0.0'}),
        ]).create();
        // Ensure we get a new mtime (mtime is only reported with 1s precision)
        await _touch('pubspec.yaml');

        await _touch('pubspec.lock');
        await _touch('.dart_tool/package_config.json');

        await _noImplicitPubGet();
      });

      test(
        "the pubspec is newer than the lockfile, but they're up-to-date",
        () async {
          await d.dir(appPath, [
            d.appPubspec(dependencies: {'foo': '1.0.0'}),
          ]).create();

          await pubGet();

          await _touch('pubspec.yaml');

          await _noImplicitPubGet();
        },
      );

      // Regression test for #1416
      test('a path dependency has a dependency on the root package', () async {
        await d.dir('foo', [
          d.libPubspec('foo', '1.0.0', deps: {'myapp': 'any'}),
        ]).create();

        await d.dir(appPath, [
          d.appPubspec(
            dependencies: {
              'foo': {'path': '../foo'},
            },
          ),
        ]).create();

        await pubGet();

        await _touch('pubspec.lock');

        await _noImplicitPubGet();
      });

      test('has a path dependency, and nothing changed', () async {
        await d.dir('foo', [d.libPubspec('foo', '1.0.0')]).create();

        await d.dir(appPath, [
          d.appPubspec(
            dependencies: {
              'foo': {'path': '../foo'},
            },
          ),
        ]).create();

        await pubGet();
        // package_config.json should not be touched as nothing changed.
        final packageConfig = File(
          p.join(d.sandbox, appPath, '.dart_tool', 'package_config.json'),
        );
        final beforeStamp = packageConfig.statSync().modified;

        await _noImplicitPubGet();

        expect(packageConfig.statSync().modified, beforeStamp);
      });

      test(
        "the lockfile is newer than package_config.json, but it's up-to-date",
        () async {
          await d.dir(appPath, [
            d.appPubspec(dependencies: {'foo': '1.0.0'}),
          ]).create();

          await pubGet();

          await _touch('pubspec.lock');

          await _noImplicitPubGet();
        },
      );

      test("an overridden dependency's SDK constraint is unmatched", () async {
        server.serve(
          'bar',
          '1.0.0',
          pubspec: {
            'environment': {'sdk': '0.0.0-fake'},
          },
        );

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dependency_overrides': {'bar': '1.0.0'},
          }),
        ]).create();

        await pubGet();

        await _touch('pubspec.lock');

        await _noImplicitPubGet();
      });
    });
  });
}

/// Runs every command that care about the world being up-to-date, and asserts
/// that it prints [message] as part of its silent output.
Future<void> _implicitPubGet(
  String message, {
  Map<String, String?>? environment,
}) async {
  final buffer = StringBuffer();
  await runEmbeddingToBuffer(
    ['pub', 'ensure-pubspec-resolved', '--verbose'],
    buffer,
    workingDirectory: d.path(appPath),
    environment: environment,
  );
  final output = buffer.toString();
  expect(output, contains('FINE: $message'));
  expect(output, contains('Resolving dependencies'));
}

/// Ensures that pub doesn't require "dart pub get" for the current package.
Future<void> _noImplicitPubGet({Map<String, String?>? environment}) async {
  final buffer = StringBuffer();
  await runEmbeddingToBuffer(
    ['pub', 'ensure-pubspec-resolved', '--verbose'],
    buffer,
    workingDirectory: d.path(appPath),
    environment: environment,
  );
  final output = buffer.toString();
  expect(output, contains('FINE: Package Config up to date.'));
  expect(output, isNot(contains('Resolving dependencies')));
  // If pub determines that everything is up-to-date, it should set the
  // mtimes to indicate that.
  final pubspecModified =
      File(p.join(d.sandbox, 'myapp/pubspec.yaml')).lastModifiedSync();
  final lockFileModified =
      File(p.join(d.sandbox, 'myapp/pubspec.lock')).lastModifiedSync();
  final packageConfigModified =
      File(
        p.join(d.sandbox, 'myapp/.dart_tool/package_config.json'),
      ).lastModifiedSync();

  expect(!pubspecModified.isAfter(lockFileModified), isTrue);
  expect(!lockFileModified.isAfter(packageConfigModified), isTrue);
}

/// Schedules a non-semantic modification to [path].
Future _touch(String path) async {
  // Delay a bit to make sure the modification times are noticeably different.
  // 1s seems to be the finest granularity that dart:io reports.
  await Future<void>.delayed(const Duration(seconds: 1));

  path = p.join(d.sandbox, 'myapp', path);
  touch(path);
}
