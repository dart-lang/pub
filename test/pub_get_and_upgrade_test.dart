// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

import 'descriptor.dart' as d;
import 'test_pub.dart';

main() {
  forBothPubGetAndUpgrade((command) {
    group('requires', () {
      test('a pubspec', () async {
        await d.dir(appPath, []).create();

        await pubCommand(command,
            error: new RegExp(r'Could not find a file named "pubspec.yaml" '
                r'in "[^\n]*"\.'),
            exitCode: exit_codes.NO_INPUT);
      }, skip: true);

      test('a pubspec with a "name" key', () async {
        await d.dir(appPath, [
          d.pubspec({
            "dependencies": {"foo": null}
          })
        ]).create();

        await pubCommand(command,
            error: contains('Missing the required "name" field.'),
            exitCode: exit_codes.DATA);
      });
    });

    test('adds itself to the packages directory and .packages file', () async {
      // The package should use the name in the pubspec, not the name of the
      // directory.
      await d.dir(appPath, [
        d.pubspec({"name": "myapp_name"}),
        d.libDir('myapp_name')
      ]).create();

      await pubCommand(command, args: ["--packages-dir"]);

      await d.dir(packagesPath, [
        d.dir("myapp_name",
            [d.file('myapp_name.dart', 'main() => "myapp_name";')])
      ]).validate();

      await d.dir("myapp", [
        d.packagesFile({"myapp_name": "."})
      ]).validate();
    });

    test(
        'does not adds itself to the packages if it has no "lib" '
        'directory', () async {
      // The symlink should use the name in the pubspec, not the name of the
      // directory.
      await d.dir(appPath, [
        d.pubspec({"name": "myapp_name"}),
      ]).create();

      await pubCommand(command, args: ["--packages-dir"]);

      await d.dir(packagesPath, [d.nothing("myapp_name")]).validate();
    });

    test(
        'does not add a package if it does not have a "lib" '
        'directory', () async {
      // Using a path source, but this should be true of all sources.
      await d.dir('foo', [d.libPubspec('foo', '0.0.0-not.used')]).create();

      await d.dir(appPath, [
        d.appPubspec({
          "foo": {"path": "../foo"}
        })
      ]).create();

      await pubCommand(command, args: ["--packages-dir"]);

      await d.packagesDir({"foo": null}).validate();
    });

    test('reports a solver failure', () async {
      // myapp depends on foo and bar which both depend on baz with mismatched
      // descriptions.
      await d.dir('deps', [
        d.dir('foo', [
          d.pubspec({
            "name": "foo",
            "dependencies": {
              "baz": {"path": "../baz1"}
            }
          })
        ]),
        d.dir('bar', [
          d.pubspec({
            "name": "bar",
            "dependencies": {
              "baz": {"path": "../baz2"}
            }
          })
        ]),
        d.dir('baz1', [d.libPubspec('baz', '0.0.0')]),
        d.dir('baz2', [d.libPubspec('baz', '0.0.0')])
      ]).create();

      await d.dir(appPath, [
        d.appPubspec({
          "foo": {"path": "../deps/foo"},
          "bar": {"path": "../deps/bar"}
        })
      ]).create();

      await pubCommand(command,
          error: new RegExp(
              r"foo from path is incompatible with bar\s+from path"));
    });

    test('does not allow a dependency on itself', () async {
      await d.dir(appPath, [
        d.appPubspec({
          "myapp": {"path": "."}
        })
      ]).create();

      await pubCommand(command,
          error: contains('A package may not list itself as a dependency.'),
          exitCode: exit_codes.DATA);
    });

    test('does not allow a dev dependency on itself', () async {
      await d.dir(appPath, [
        d.pubspec({
          "name": "myapp",
          "dev_dependencies": {
            "myapp": {"path": "."}
          }
        })
      ]).create();

      await pubCommand(command,
          error: contains('A package may not list itself as a dependency.'),
          exitCode: exit_codes.DATA);
    });
  });
}
