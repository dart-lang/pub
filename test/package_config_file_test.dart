// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE d.file.

import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

import 'descriptor.dart' as d;
import 'test_pub.dart';

void main() {
  forBothPubGetAndUpgrade((command) {
    test('package_config.json file is created', () async {
      await servePackages((builder) {
        builder.serve('foo', '1.2.3',
            deps: {'baz': '2.2.2'}, contents: [d.dir('lib', [])]);
        builder.serve('bar', '3.2.1', contents: [d.dir('lib', [])]);
        builder.serve('baz', '2.2.2',
            deps: {'bar': '3.2.1'}, contents: [d.dir('lib', [])]);
      });

      await d.dir(appPath, [
        d.appPubspec({'foo': '1.2.3'}),
        d.dir('lib')
      ]).create();

      await pubCommand(command);

      await d.dir(appPath, [
        d.packageConfigFile([
          d.packageConfigEntry(
            name: 'foo',
            version: '1.2.3',
          ),
          d.packageConfigEntry(
            name: 'bar',
            version: '3.2.1',
          ),
          d.packageConfigEntry(
            name: 'baz',
            version: '2.2.2',
          ),
          d.packageConfigEntry(
            name: 'myapp',
            path: '.',
          ),
        ]),
      ]).validate();
    });

    test('package_config.json file is overwritten', () async {
      await servePackages((builder) {
        builder.serve('foo', '1.2.3',
            deps: {'baz': '2.2.2'}, contents: [d.dir('lib', [])]);
        builder.serve('bar', '3.2.1', contents: [d.dir('lib', [])]);
        builder.serve('baz', '2.2.2',
            deps: {'bar': '3.2.1'}, contents: [d.dir('lib', [])]);
      });

      await d.dir(appPath, [
        d.appPubspec({'foo': '1.2.3'}),
        d.dir('lib')
      ]).create();

      var oldFile = d.dir(appPath, [
        d.packageConfigFile([
          d.packageConfigEntry(
            name: 'notFoo',
            version: '9.9.9',
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
          ),
          d.packageConfigEntry(
            name: 'bar',
            version: '3.2.1',
          ),
          d.packageConfigEntry(
            name: 'baz',
            version: '2.2.2',
          ),
          d.packageConfigEntry(
            name: 'myapp',
            path: '.',
          ),
        ]),
      ]).validate();
    });

    test('package_config.json file is not created if pub fails', () async {
      await d.dir(appPath, [
        d.appPubspec({'foo': '1.2.3'}),
        d.dir('lib')
      ]).create();

      await pubCommand(command,
          args: ['--offline'], error: equalsIgnoringWhitespace("""
            Because myapp depends on foo any which doesn't exist (could not find
              package foo in cache), version solving failed.
          """), exitCode: exit_codes.UNAVAILABLE);

      await d.dir(appPath, [
        d.nothing('.dart_tool/package_config.json'),
      ]).validate();
    });

    test(
        '.dart_tool/package_config.json file has relative path to path dependency',
        () async {
      await servePackages((builder) {
        builder.serve('foo', '1.2.3',
            deps: {'baz': 'any'}, contents: [d.dir('lib', [])]);
        builder.serve('baz', '9.9.9', deps: {}, contents: [d.dir('lib', [])]);
      });

      await d.dir('local_baz', [
        d.libDir('baz', 'baz 3.2.1'),
        d.libPubspec('baz', '3.2.1')
      ]).create();

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependencies': {
            'foo': '^1.2.3',
          },
          'dependency_overrides': {
            'baz': {'path': '../local_baz'},
          }
        }),
        d.dir('lib')
      ]).create();

      await pubCommand(command);

      await d.dir(appPath, [
        d.packageConfigFile([
          d.packageConfigEntry(
            name: 'foo',
            version: '1.2.3',
          ),
          d.packageConfigEntry(
            name: 'baz',
            path: '../local_baz',
          ),
          d.packageConfigEntry(
            name: 'myapp',
            path: '.',
          ),
        ]),
      ]).validate();
    });

    test('package_config.json has language version', () async {
      await servePackages((builder) {
        builder.serve(
          'foo',
          '1.2.3',
          pubspec: {
            'environment': {
              'sdk': '>=0.0.1 <=0.2.2+2', // tests runs with '0.1.2+3'
            },
          },
          contents: [d.dir('lib', [])],
        );
      });

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependencies': {
            'foo': '^1.2.3',
          },
          'environment': {
            'sdk': '>=0.1.0 <=0.2.2+2', // tests runs with '0.1.2+3'
          },
        }),
        d.dir('lib')
      ]).create();

      await pubCommand(command);

      await d.dir(appPath, [
        d.packageConfigFile([
          d.packageConfigEntry(
            name: 'foo',
            version: '1.2.3',
            languageVersion: '0.0',
          ),
          d.packageConfigEntry(
            name: 'myapp',
            path: '.',
            languageVersion: '0.1',
          ),
        ]),
      ]).validate();
    });

    test('package_config.json has no default language version', () async {
      await servePackages((builder) {
        builder.serve(
          'foo',
          '1.2.3',
          pubspec: {
            'environment': {
              'sdk': '>=0.0.1 <=0.2.2+2', // tests runs with '0.1.2+3'
            },
          },
          contents: [d.dir('lib', [])],
        );
      });

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependencies': {
            'foo': '^1.2.3',
          },
        }),
        d.dir('lib')
      ]).create();

      await pubCommand(command);

      await d.dir(appPath, [
        d.packageConfigFile([
          d.packageConfigEntry(
            name: 'foo',
            version: '1.2.3',
            languageVersion: '0.0',
          ),
          d.packageConfigEntry(
            name: 'myapp',
            path: '.',
          ),
        ]),
      ]).validate();
    });
  });
}
