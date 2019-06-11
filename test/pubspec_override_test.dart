// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:path/path.dart' as path;

import 'descriptor.dart' as d;
import 'test_pub.dart';

main() {
  forBothPubGetAndUpgrade((command) {
    test("chooses best version matching override constraint", () async {
      await servePackages((builder) {
        builder.serve("foo", "1.0.0");
        builder.serve("foo", "2.0.0");
        builder.serve("foo", "3.0.0");
      });

      await d.dir(appPath, [
        d.pubspec({
          "name": "myapp",
          "dependencies": {"foo": ">2.0.0"},
        }),
        d.pubspecOverride({
          "dependencies": {"foo": "<3.0.0"}
        })
      ]).create();

      await pubCommand(command);

      await d.appPackagesFile({"foo": "2.0.0"}).validate();
    });

    test("treats override as implicit dependency", () async {
      await servePackages((builder) {
        builder.serve("foo", "1.0.0");
      });

      await d.dir(appPath, [
        d.pubspec({
          "name": "myapp"
        }),
        d.pubspecOverride({
          "dependencies": {"foo": "any"}
        })
      ]).create();

      await pubCommand(command);

      await d.appPackagesFile({"foo": "1.0.0"}).validate();
    });

    test("ignores SDK constraints", () async {
      await servePackages((builder) {
        builder.serve("foo", "1.0.0", pubspec: {
          "environment": {"sdk": "5.6.7-fblthp"}
        });
      });

      await d.dir(appPath, [
        d.pubspec({
          "name": "myapp",
          "dependency_overrides": {"foo": "0.0.9"}
        }),
        d.pubspecOverride({
          "dependency_overrides": {"foo": "any"}
        })
      ]).create();

      await pubCommand(command);

      await d.appPackagesFile({"foo": "1.0.0"}).validate();
    });

    test("uses overridden version correctly", () async {
      await servePackages((builder) {
        builder.serve("foo", "1.0.0");
        builder.serve("foo", "2.0.0");
        builder.serve("foo", "3.0.0");
        builder.serve("bar", "1.0.0");
      });

      await d.dir(appPath, [
        d.pubspec({
          "name": "myapp",
          "dependencies": {"foo": "<2.0.0"},
          "dev_dependencies": {"bar": "1.0.0"}
        }),
        d.pubspecOverride({
          "dependencies": {"foo": "<3.0.0"},
          "dev_dependencies": {
            "bar": {"path": "../bardev"}
          }
        })
      ]).create();

      await d
          .dir("bardev", [d.libDir("bar"), d.libPubspec("bar", "0.0.1")]).create();
      var bardevPath = path.join("..", "bardev");

      await pubCommand(command);

      await d.appPackagesFile({"foo": "2.0.0", "bar": "$bardevPath"}).validate();
    });

//TODO: warn about overrides in pubspec.override.yaml
  //   test("warns about overridden dependencies", () async {
  //     await servePackages((builder) {
  //       builder.serve("foo", "1.0.0");
  //       builder.serve("bar", "1.0.0");
  //     });

  //     await d
  //         .dir("baz", [d.libDir("baz"), d.libPubspec("baz", "0.0.1")]).create();

  //     await d.dir(appPath, [
  //       d.pubspec({
  //         "name": "myapp",
  //         "dependency_overrides": {
  //           "foo": "any",
  //           "bar": "any",
  //           "baz": {"path": "../baz"}
  //         }
  //       })
  //     ]).create();

  //     var bazPath = path.join("..", "baz");

  //     await runPub(
  //         args: [command.name],
  //         output: command.success,
  //         error: """
  //         Warning: You are using these overridden dependencies:
  //         ! bar 1.0.0
  //         ! baz 0.0.1 from path $bazPath
  //         ! foo 1.0.0
  //         """);
  //   });
  });
}
