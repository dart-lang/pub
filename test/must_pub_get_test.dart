// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:pub/src/io.dart';
import 'package:scheduled_test/scheduled_stream.dart';
import 'package:scheduled_test/scheduled_test.dart';

import 'descriptor.dart' as d;
import 'test_pub.dart';

main() {
  setUp(() {
    servePackages((builder) {
      builder.serve("foo", "1.0.0");
      builder.serve("foo", "2.0.0");
    });

    d.dir(appPath, [
      d.appPubspec(),
      d.dir("web", []),
      d.dir("bin", [
        d.file("script.dart", "main() => print('hello!');")
      ])
    ]).create();

    pubGet();
  });

  group("requires the user to run pub get first if", () {
    group("there's no lockfile", () {
      setUp(() {
        schedule(() => deleteEntry(p.join(sandboxDir, "myapp/pubspec.lock")));
      });

      _requiresPubGet(
          'No pubspec.lock file found, please run "pub get" first.');
    });

    group("there's no package spec", () {
      setUp(() {
        schedule(() => deleteEntry(p.join(sandboxDir, "myapp/.packages")));
      });

      _requiresPubGet('No .packages file found, please run "pub get" first.');
    });

    group("the pubspec has a new dependency", () {
      setUp(() {
        d.dir("foo", [
          d.libPubspec("foo", "1.0.0")
        ]).create();

        d.dir(appPath, [
          d.appPubspec({"foo": {"path": "../foo"}})
        ]).create();

        // Ensure that the pubspec looks newer than the lockfile.
        _touch("pubspec.yaml");
      });

      _requiresPubGet('The pubspec.yaml file has changed since the '
          'pubspec.lock file was generated, please run "pub get" again.');
    });

    group("the lockfile has a dependency from the wrong source", () {
      setUp(() {
        d.dir(appPath, [
          d.appPubspec({"foo": "1.0.0"})
        ]).create();

        pubGet();

        createLockFile(appPath, sandbox: ["foo"]);

        // Ensure that the pubspec looks newer than the lockfile.
        _touch("pubspec.yaml");
      });

      _requiresPubGet('The pubspec.yaml file has changed since the '
          'pubspec.lock file was generated, please run "pub get" again.');
    });

    group("the lockfile has a dependency from an unknown source", () {
      setUp(() {
        d.dir(appPath, [
          d.appPubspec({"foo": "1.0.0"})
        ]).create();

        pubGet();

        d.dir(appPath, [
          d.file("pubspec.lock", yaml({
            "packages": {
              "foo": {
                "description": "foo", 
                "version": "1.0.0",
                "source": "sdk"
              }
            }
          }))
        ]).create();

        // Ensure that the pubspec looks newer than the lockfile.
        _touch("pubspec.yaml");
      });

      _requiresPubGet('The pubspec.yaml file has changed since the '
          'pubspec.lock file was generated, please run "pub get" again.');
    });

    group("the lockfile has a dependency with the wrong description", () {
      setUp(() {
        d.dir("bar", [
          d.libPubspec("foo", "1.0.0")
        ]).create();

        d.dir(appPath, [
          d.appPubspec({"foo": {"path": "../bar"}})
        ]).create();

        pubGet();

        createLockFile(appPath, sandbox: ["foo"]);

        // Ensure that the pubspec looks newer than the lockfile.
        _touch("pubspec.yaml");
      });

      _requiresPubGet('The pubspec.yaml file has changed since the '
          'pubspec.lock file was generated, please run "pub get" again.');
    });

    group("the pubspec has an incompatible version of a dependency", () {
      setUp(() {
        d.dir(appPath, [
          d.appPubspec({"foo": "1.0.0"})
        ]).create();

        pubGet();

        d.dir(appPath, [
          d.appPubspec({"foo": "2.0.0"})
        ]).create();

        // Ensure that the pubspec looks newer than the lockfile.
        _touch("pubspec.yaml");
      });

      _requiresPubGet('The pubspec.yaml file has changed since the '
          'pubspec.lock file was generated, please run "pub get" again.');
    });

    group("the lockfile is pointing to an unavailable package with a newer "
        "pubspec", () {
      setUp(() {
        d.dir(appPath, [
          d.appPubspec({"foo": "1.0.0"})
        ]).create();

        pubGet();

        schedule(() => deleteEntry(p.join(sandboxDir, cachePath)));

        // Ensure that the pubspec looks newer than the lockfile.
        _touch("pubspec.yaml");
      });

      _requiresPubGet('The pubspec.yaml file has changed since the '
          'pubspec.lock file was generated, please run "pub get" again.');
    });

    group("the lockfile is pointing to an unavailable package with an older "
        ".packages", () {
      setUp(() {
        d.dir(appPath, [
          d.appPubspec({"foo": "1.0.0"})
        ]).create();

        pubGet();

        schedule(() => deleteEntry(p.join(sandboxDir, cachePath)));

        // Ensure that the lockfile looks newer than the .packages file.
        _touch("pubspec.lock");
      });

      _requiresPubGet('The pubspec.lock file has changed since the .packages '
          'file was generated, please run "pub get" again.');
    });

    group("the lockfile has a package that the .packages file doesn't", () {
      setUp(() {
        d.dir("foo", [
          d.libPubspec("foo", "1.0.0")
        ]).create();

        d.dir(appPath, [
          d.appPubspec({"foo": {"path": "../foo"}})
        ]).create();

        pubGet();

        createPackagesFile(appPath);

        // Ensure that the pubspec looks newer than the lockfile.
        _touch("pubspec.lock");
      });

      _requiresPubGet('The pubspec.lock file has changed since the .packages '
          'file was generated, please run "pub get" again.');
    });

    group("the .packages file has a package with a non-file URI", () {
      setUp(() {
        d.dir("foo", [
          d.libPubspec("foo", "1.0.0")
        ]).create();

        d.dir(appPath, [
          d.appPubspec({"foo": {"path": "../foo"}})
        ]).create();

        pubGet();

        d.dir(appPath, [
          d.file(".packages", """
myapp:lib
foo:http://example.com/
""")
        ]).create();

        // Ensure that the pubspec looks newer than the lockfile.
        _touch("pubspec.lock");
      });

      _requiresPubGet('The pubspec.lock file has changed since the .packages '
          'file was generated, please run "pub get" again.');
    });

    group("the .packages file points to the wrong place", () {
      setUp(() {
        d.dir("bar", [
          d.libPubspec("foo", "1.0.0")
        ]).create();

        d.dir(appPath, [
          d.appPubspec({"foo": {"path": "../bar"}})
        ]).create();

        pubGet();

        createPackagesFile(appPath, sandbox: ["foo"]);

        // Ensure that the pubspec looks newer than the lockfile.
        _touch("pubspec.lock");
      });

      _requiresPubGet('The pubspec.lock file has changed since the .packages '
          'file was generated, please run "pub get" again.');
    });

    group("the lock file's SDK constraint doesn't match the current SDK", () {
      setUp(() {
        // Avoid using a path dependency because it triggers the full validation
        // logic. We want to be sure SDK-validation works without that logic.
        servePackages((builder) {
          builder.serve("foo", "3.0.0", pubspec: {
            "environment": {"sdk": ">=1.0.0 <2.0.0"}
          });
        });

        d.dir(appPath, [
          d.appPubspec({"foo": "3.0.0"})
        ]).create();

        pubGet(environment: {"_PUB_TEST_SDK_VERSION": "1.2.3+4"});
      });

      _requiresPubGet("Dart 0.1.2+3 is incompatible with your dependencies' "
          "SDK constraints. Please run \"pub get\" again.");
    }, skip: "Times out. Issue https://github.com/dart-lang/pub/issues/1389");

    group("a path dependency's dependency doesn't match the lockfile", () {
      setUp(() {
        d.dir("bar", [
          d.libPubspec("bar", "1.0.0", deps: {"foo": "1.0.0"})
        ]).create();

        d.dir(appPath, [
          d.appPubspec({"foo": {"path": "../foo"}})
        ]);

        pubGet();

        // Update foo's pubspec without touching the app's.
        d.dir("bar", [
          d.libPubspec("bar", "1.0.0", deps: {"foo": "2.0.0"})
        ]).create();
      });
    });
  });

  group("doesn't require the user to run pub get first if", () {
    group("the pubspec is older than the lockfile which is older than the "
        "packages file, even if the contents are wrong", () {
      setUp(() {
        d.dir(appPath, [
          d.appPubspec({"foo": "1.0.0"})
        ]).create();

        _touch("pubspec.lock");
        _touch(".packages");
      });

      _runsSuccessfully(runDeps: false);
    });

    group("the pubspec is newer than the lockfile, but they're up-to-date", () {
      setUp(() {
        d.dir(appPath, [
          d.appPubspec({"foo": "1.0.0"})
        ]).create();

        pubGet();

        _touch("pubspec.yaml");
      });

      _runsSuccessfully();
    });

    group("the lockfile is newer than .packages, but they're up-to-date", () {
      setUp(() {
        d.dir(appPath, [
          d.appPubspec({"foo": "1.0.0"})
        ]).create();

        pubGet();

        _touch("pubspec.lock");
      });

      _runsSuccessfully();
    });
  });
}

/// Runs every command that care about the world being up-to-date, and asserts
/// that it prints [message] as part of its error.
void _requiresPubGet(String message) {
  for (var command in ["build", "serve", "run", "deps"]) {
    integration("for pub $command", () {
      var args = [command];
      if (command == "run") args.add("script");

      schedulePub(
          args: args,
          error: contains(message),
          exitCode: exit_codes.DATA);
    });
  }
}

/// Ensures that pub doesn't require "pub get" for the current package.
///
/// If [runDeps] is false, `pub deps` isn't included in the test. This is
/// sometimes not desirable, since it uses slightly stronger checks for pubspec
/// and lockfile consistency.
void _runsSuccessfully({bool runDeps: true}) {
  var commands = ["build", "serve", "run"];
  if (runDeps) commands.add("deps");

  for (var command in commands) {
    integration("for pub $command", () {
      var args = [command];
      if (command == "run") args.add("bin/script.dart");
      if (command == "serve") ;

      if (command != "serve") {
        schedulePub(args: args);
      } else {
        var pub = startPub(args: ["serve", "--port=0"]);
        pub.stdout.expect(consumeThrough(startsWith("Serving myapp web")));
        pub.kill();
      }

      schedule(() {
        // If pub determines that everything is up-to-date, it should set the
        // mtimes to indicate that.
        var pubspecModified = new File(p.join(sandboxDir, "myapp/pubspec.yaml"))
            .lastModifiedSync();
        var lockFileModified =
            new File(p.join(sandboxDir, "myapp/pubspec.lock"))
                .lastModifiedSync();
        var packagesModified = new File(p.join(sandboxDir, "myapp/.packages"))
            .lastModifiedSync();

        expect(!pubspecModified.isAfter(lockFileModified), isTrue);
        expect(!lockFileModified.isAfter(packagesModified), isTrue);
      }, "testing last-modified times");
    });
  }
}

/// Schedules a non-semantic modification to [path].
void _touch(String path) {
  schedule(() async {
    // Delay a bit to make sure the modification times are noticeably different.
    // 1s seems to be the finest granularity that dart:io reports.
    await new Future.delayed(new Duration(seconds: 1));

    path = p.join(sandboxDir, "myapp", path);
    touch(path);
  }, "touching $path");
}
