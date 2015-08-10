// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:pub/src/io.dart';
import 'package:scheduled_test/scheduled_test.dart';

import 'descriptor.dart' as d;
import 'test_pub.dart';

main() {
  group("requires the user to run pub get first if", () {
    setUp(() {
      d.dir(appPath, [
        d.appPubspec(),
        d.dir("web", []),
        d.dir("bin", [
          d.file("script.dart", "main() => print('hello!');")
        ])
      ]).create();

      pubGet();

      // Delay a bit to make sure the modification times are noticeably
      // different. 1s seems to be the finest granularity that dart:io reports.
      schedule(() => new Future.delayed(new Duration(seconds: 1)));
    });

    group("there's no lockfile", () {
      setUp(() {
        schedule(() => deleteEntry(p.join(sandboxDir, "myapp/pubspec.lock")));
      });

      _forEveryCommand(
          'No pubspec.lock file found, please run "pub get" first.');
    });

    group("there's no package spec", () {
      setUp(() {
        schedule(() => deleteEntry(p.join(sandboxDir, "myapp/.packages")));
      });

      _forEveryCommand('No .packages file found, please run "pub get" first.');
    });

    group("the pubspec is newer than the package spec", () {
      setUp(() {
        schedule(() => _touch("pubspec.yaml"));
      });

      _forEveryCommand('The pubspec.yaml file has changed since the .packages '
          'file was generated, please run "pub get" again.');
    });

    group("the lockfile is newer than the package spec", () {
      setUp(() {
        schedule(() => _touch("pubspec.lock"));
      });

      _forEveryCommand('The pubspec.lock file has changed since the .packages '
          'file was generated, please run "pub get" again.');
    });
  });
}

/// Runs every command that care about the world being up-to-date, and asserts
/// that it prints [message] as part of its error.
void _forEveryCommand(String message) {
  for (var command in ["build", "serve", "run", "deps"]) {
    integration("for pub $command", () {
      var args = [command];
      if (command == "run") args.add("script");

      var output;
      var error;
      if (command == "list-package-dirs") {
        output = contains(JSON.encode(message));
      } else {
        error = contains(message);
      }

      schedulePub(
          args: args,
          output: output,
          error: error,
          exitCode: exit_codes.DATA);
    });
  }
}

void _touch(String path) {
  path = p.join(sandboxDir, "myapp", path);
  writeTextFile(path, readTextFile(path) + " ");
}
