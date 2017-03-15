// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:scheduled_test/scheduled_test.dart';

import 'descriptor.dart' as d;
import 'test_pub.dart';

main() {
  forBothPubGetAndUpgrade((command) {
    group('requires', () {
      integration('a pubspec', () {
        d.dir(appPath, []).create();

        pubCommand(command,
            error: new RegExp(r'Could not find a file named "pubspec.yaml" '
                r'in "[^\n]*"\.'));
      });

      integration('a pubspec with a "name" key', () {
        d.dir(appPath, [
          d.pubspec({
            "dependencies": {"foo": null}
          })
        ]).create();

        pubCommand(command,
            error: contains('Missing the required "name" field.'),
            exitCode: exit_codes.DATA);
      });
    });

    integration('adds itself to the packages directory and .packages file', () {
      // The package should use the name in the pubspec, not the name of the
      // directory.
      d.dir(appPath, [
        d.pubspec({"name": "myapp_name"}),
        d.libDir('myapp_name')
      ]).create();

      pubCommand(command, args: ["--packages-dir"]);

      d.dir(packagesPath, [
        d.dir("myapp_name",
            [d.file('myapp_name.dart', 'main() => "myapp_name";')])
      ]).validate();

      d.dir("myapp", [
        d.packagesFile({"myapp_name": "."})
      ]).validate();
    });

    integration(
        'does not adds itself to the packages if it has no "lib" '
        'directory', () {
      // The symlink should use the name in the pubspec, not the name of the
      // directory.
      d.dir(appPath, [
        d.pubspec({"name": "myapp_name"}),
      ]).create();

      pubCommand(command, args: ["--packages-dir"]);

      d.dir(packagesPath, [d.nothing("myapp_name")]).validate();
    });

    integration(
        'does not add a package if it does not have a "lib" '
        'directory', () {
      // Using a path source, but this should be true of all sources.
      d.dir('foo', [d.libPubspec('foo', '0.0.0-not.used')]).create();

      d.dir(appPath, [
        d.appPubspec({
          "foo": {"path": "../foo"}
        })
      ]).create();

      pubCommand(command, args: ["--packages-dir"]);

      d.packagesDir({"foo": null}).validate();
    });

    integration('reports a solver failure', () {
      // myapp depends on foo and bar which both depend on baz with mismatched
      // descriptions.
      d.dir('deps', [
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

      d.dir(appPath, [
        d.appPubspec({
          "foo": {"path": "../deps/foo"},
          "bar": {"path": "../deps/bar"}
        })
      ]).create();

      pubCommand(command,
          error: new RegExp("^Incompatible dependencies on baz:\n"));
    });

    integration('does not allow a dependency on itself', () {
      d.dir(appPath, [
        d.appPubspec({
          "myapp": {"path": "."}
        })
      ]).create();

      pubCommand(command,
          error: contains('A package may not list itself as a dependency.'),
          exitCode: exit_codes.DATA);
    });

    integration('does not allow a dev dependency on itself', () {
      d.dir(appPath, [
        d.pubspec({
          "name": "myapp",
          "dev_dependencies": {
            "myapp": {"path": "."}
          }
        })
      ]).create();

      pubCommand(command,
          error: contains('A package may not list itself as a dependency.'),
          exitCode: exit_codes.DATA);
    });
  });
}
