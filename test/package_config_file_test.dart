// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:pub/src/package_config.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart';

import 'descriptor.dart' as d;
import 'test_pub.dart';

void main() {
  forBothPubGetAndUpgrade((command) {
    test('package_config.json file is created', () async {
      await servePackages()
        ..serve(
          'foo',
          '1.2.3',
          deps: {'baz': '2.2.2'},
          contents: [d.dir('lib', [])],
        )
        ..serve('bar', '3.2.1', contents: [d.dir('lib', [])])
        ..serve(
          'baz',
          '2.2.2',
          deps: {'bar': '3.2.1'},
          contents: [d.dir('lib', [])],
        );

      await d.dir(appPath, [
        d.appPubspec(dependencies: {'foo': '1.2.3'}),
        d.dir('lib'),
      ]).create();

      await pubCommand(command);

      await d.dir(appPath, [
        d.packageConfigFile([
          d.packageConfigEntry(
            name: 'foo',
            version: '1.2.3',
            languageVersion: '3.0',
          ),
          d.packageConfigEntry(
            name: 'bar',
            version: '3.2.1',
            languageVersion: '3.0',
          ),
          d.packageConfigEntry(
            name: 'baz',
            version: '2.2.2',
            languageVersion: '3.0',
          ),
          d.packageConfigEntry(
            name: 'myapp',
            path: '.',
            languageVersion: '3.0',
          ),
        ]),
      ]).validate();
    });

    test(
      'package_config.json uses relative paths if PUB_CACHE is relative',
      () async {
        final server = await servePackages();
        server.serve('foo', '1.2.3');

        await d.dir(appPath, [
          d.appPubspec(dependencies: {'foo': '1.2.3'}),
        ]).create();

        await pubCommand(command, environment: {'PUB_CACHE': './pub_cache'});

        await d.dir(appPath, [
          d.packageConfigFile([
            PackageConfigEntry(
              name: 'foo',
              rootUri: p.toUri(
                '../pub_cache/hosted/localhost%58${globalServer.port}/foo-1.2.3',
              ),
              packageUri: Uri.parse('lib/'),
            ),
            d.packageConfigEntry(
              name: 'myapp',
              path: '.',
              languageVersion: '3.0',
            ),
          ], pubCache: p.join(d.sandbox, appPath, 'pub_cache')),
        ]).validate();
      },
    );

    test('package_config.json file is overwritten', () async {
      await servePackages()
        ..serve(
          'foo',
          '1.2.3',
          deps: {'baz': '2.2.2'},
          contents: [d.dir('lib', [])],
        )
        ..serve('bar', '3.2.1', contents: [d.dir('lib', [])])
        ..serve(
          'baz',
          '2.2.2',
          deps: {'bar': '3.2.1'},
          contents: [d.dir('lib', [])],
        );

      await d.dir(appPath, [
        d.appPubspec(dependencies: {'foo': '1.2.3'}),
        d.dir('lib'),
      ]).create();

      final oldFile = d.dir(appPath, [
        d.packageConfigFile([
          d.packageConfigEntry(
            name: 'notFoo',
            version: '9.9.9',
            languageVersion: '2.7',
          ),
        ]),
      ]);
      await oldFile.create();
      await oldFile.validate(); // Sanity-check that file was created correctly.

      await pubCommand(command);

      await d.dir(appPath, [
        d.packageConfigFile([
          d.packageConfigEntry(
            name: 'foo',
            version: '1.2.3',
            languageVersion: '3.0',
          ),
          d.packageConfigEntry(
            name: 'bar',
            version: '3.2.1',
            languageVersion: '3.0',
          ),
          d.packageConfigEntry(
            name: 'baz',
            version: '2.2.2',
            languageVersion: '3.0',
          ),
          d.packageConfigEntry(
            name: 'myapp',
            path: '.',
            languageVersion: '3.0',
          ),
        ]),
      ]).validate();
    });

    test('package_config.json file is not created if pub fails', () async {
      await d.dir(appPath, [
        d.appPubspec(dependencies: {'foo': '1.2.3'}),
        d.dir('lib'),
      ]).create();

      await pubCommand(
        command,
        args: ['--offline'],
        error: equalsIgnoringWhitespace("""
            Because myapp depends on foo any which doesn't exist (could not find
              package foo in cache), version solving failed.

            Try again without --offline!
          """),
        exitCode: exit_codes.UNAVAILABLE,
      );

      await d.dir(appPath, [
        d.nothing('.dart_tool/package_config.json'),
      ]).validate();
    });

    test(
      '.dart_tool/package_config.json file has relative path to path dependency',
      () async {
        await servePackages()
          ..serve(
            'foo',
            '1.2.3',
            deps: {'baz': 'any'},
            contents: [d.dir('lib', [])],
          )
          ..serve('baz', '9.9.9', deps: {}, contents: [d.dir('lib', [])]);

        await d.dir('local_baz', [
          d.libDir('baz', 'baz 3.2.1'),
          d.pubspec({'name': 'baz', 'version': '3.2.1'}),
        ]).create();

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dependencies': {'foo': '^1.2.3'},
            'dependency_overrides': {
              'baz': {'path': '../local_baz'},
            },
          }),
          d.dir('lib'),
        ]).create();

        await pubCommand(command);

        await d.dir(appPath, [
          d.packageConfigFile([
            d.packageConfigEntry(
              name: 'foo',
              version: '1.2.3',
              languageVersion: '3.0',
            ),
            d.packageConfigEntry(
              name: 'baz',
              path: '../local_baz',
              languageVersion: '3.0',
            ),
            d.packageConfigEntry(
              name: 'myapp',
              path: '.',
              languageVersion: '3.0',
            ),
          ]),
        ]).validate();
      },
    );

    test('package_config.json has language version', () async {
      final server = await servePackages();
      server.serve(
        'foo',
        '1.2.3',
        pubspec: {
          'environment': {
            'sdk': '>=3.0.1 <=3.2.2+2', // tests runs with '3.1.2+3'
          },
        },
        contents: [d.dir('lib', [])],
      );

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependencies': {'foo': '^1.2.3'},
          'environment': {
            'sdk': '>=3.1.0 <=3.2.2+2', // tests runs with '3.1.2+3'
          },
        }),
        d.dir('lib'),
      ]).create();

      await pubCommand(command);

      await d.dir(appPath, [
        d.packageConfigFile([
          d.packageConfigEntry(
            name: 'foo',
            version: '1.2.3',
            languageVersion: '3.0',
          ),
          d.packageConfigEntry(
            name: 'myapp',
            path: '.',
            languageVersion: '3.1',
          ),
        ]),
      ]).validate();
    });

    test('package_config.json has 2.7 default language version', () async {
      // TODO(sigurdm): Reconsider the default language version for dart 3.
      final server = await servePackages();
      server.serve(
        'foo',
        '1.2.3',
        pubspec: {
          'environment': {'sdk': '<4.0.0'},
        },
        contents: [d.dir('lib', [])],
      );

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependencies': {'foo': '^1.2.3'},
        }),
        d.dir('lib'),
      ]).create();

      await pubCommand(command);

      await d.dir(appPath, [
        d.packageConfigFile([
          d.packageConfigEntry(
            name: 'foo',
            version: '1.2.3',
            languageVersion: '2.7',
          ),
          d.packageConfigEntry(
            name: 'myapp',
            path: '.',
            languageVersion: '3.0',
          ),
        ]),
      ]).validate();
    });
  });

  test('pubspec.lock, package_config, package_graph and workspace_ref '
      'are not rewritten if unchanged', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');

    await d.dir(appPath, [
      d.appPubspec(
        dependencies: {'foo': 'any'},
        extras: {
          'workspace': ['foo'],
          'environment': {'sdk': '^3.5.0'},
        },
      ),
      d.dir('foo', [d.libPubspec('foo', '1.0.0', resolutionWorkspace: true)]),
    ]).create();

    await pubGet(environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'});
    final packageConfigFile = File(
      p.join(sandbox, appPath, '.dart_tool', 'package_config.json'),
    );
    final packageConfig = jsonDecode(packageConfigFile.readAsStringSync());
    final packageConfigTimestamp = packageConfigFile.lastModifiedSync();
    final lockFile = File(p.join(sandbox, appPath, 'pubspec.lock'));
    final lockfileTimestamp = lockFile.lastModifiedSync();
    final packageGraphFile = File(
      p.join(sandbox, appPath, '.dart_tool', 'package_graph.json'),
    );
    final packageGraph = jsonDecode(packageGraphFile.readAsStringSync());
    final packageGraphTimestamp = packageGraphFile.lastModifiedSync();
    final workspaceRefFile = File(
      p.join(
        sandbox,
        appPath,
        'foo',
        '.dart_tool',
        'pub',
        'workspace_ref.json',
      ),
    );
    final workspaceRefTimestamp = workspaceRefFile.lastModifiedSync();
    final s = p.separator;
    await pubGet(
      silent: allOf(
        contains(
          '`.dart_tool${s}package_config.json` is unchanged. Not rewriting.',
        ),
        contains(
          '`.dart_tool${s}package_graph.json` is unchanged. Not rewriting.',
        ),
      ),
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
    );
    // The resolution of timestamps is not that good.
    await Future<Null>.delayed(const Duration(seconds: 1));
    expect(packageConfig, jsonDecode(packageConfigFile.readAsStringSync()));
    expect(packageConfigFile.lastModifiedSync(), packageConfigTimestamp);

    expect(packageGraph, jsonDecode(packageGraphFile.readAsStringSync()));
    expect(packageGraphFile.lastModifiedSync(), packageGraphTimestamp);

    expect(lockFile.lastModifiedSync(), lockfileTimestamp);
    expect(workspaceRefFile.lastModifiedSync(), workspaceRefTimestamp);
  });
}
