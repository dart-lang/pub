// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

import 'descriptor.dart' as d;
import 'test_pub.dart';

void main() {
  forBothPubGetAndUpgrade((command) {
    group('requires', () {
      test('a pubspec', () async {
        await d.dir(appPath, []).create();

        await pubCommand(command,
            error: RegExp(r'Could not find a file named "pubspec.yaml" '
                r'in "[^\n]*"\.'),
            exitCode: exit_codes.NO_INPUT);
      });

      test('a pubspec with a "name" key', () async {
        await d.dir(appPath, [
          d.pubspec({
            'dependencies': {'foo': null}
          })
        ]).create();

        await pubCommand(command,
            error: contains('Missing the required "name" field.'),
            exitCode: exit_codes.DATA);
      });
    });

    test('adds itself to the .packages file', () async {
      // The package should use the name in the pubspec, not the name of the
      // directory.
      await d.dir(appPath, [
        d.pubspec({'name': 'myapp_name'}),
        d.libDir('myapp_name')
      ]).create();

      await pubCommand(command);

      await d.dir('myapp', [
        d.packagesFile({'myapp_name': '.'})
      ]).validate();
    });

    test('reports a solver failure', () async {
      // myapp depends on foo and bar which both depend on baz with mismatched
      // descriptions.
      await d.dir('deps', [
        d.dir('foo', [
          d.pubspec({
            'name': 'foo',
            'dependencies': {
              'baz': {'path': '../baz1'}
            }
          })
        ]),
        d.dir('bar', [
          d.pubspec({
            'name': 'bar',
            'dependencies': {
              'baz': {'path': '../baz2'}
            }
          })
        ]),
        d.dir('baz1', [d.libPubspec('baz', '0.0.0')]),
        d.dir('baz2', [d.libPubspec('baz', '0.0.0')])
      ]).create();

      await d.dir(appPath, [
        d.appPubspec({
          'foo': {'path': '../deps/foo'},
          'bar': {'path': '../deps/bar'}
        })
      ]).create();

      await pubCommand(command,
          error: RegExp(r'bar from path is incompatible with foo from path'));
    });

    test('does not allow a dependency on itself', () async {
      await d.dir(appPath, [
        d.appPubspec({
          'myapp': {'path': '.'}
        })
      ]).create();

      await pubCommand(command,
          error: contains('A package may not list itself as a dependency.'),
          exitCode: exit_codes.DATA);
    });

    test('does not allow a dev dependency on itself', () async {
      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dev_dependencies': {
            'myapp': {'path': '.'}
          }
        })
      ]).create();

      await pubCommand(command,
          error: contains('A package may not list itself as a dependency.'),
          exitCode: exit_codes.DATA);
    });
  });
}
