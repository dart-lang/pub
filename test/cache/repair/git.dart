// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as path;
import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:pub/src/io.dart';
import 'package:scheduled_test/scheduled_test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

main() {
  setUp(() {
    // Create two cached revisions of foo.
    d.git('foo.git', [
      d.libDir('foo'),
      d.libPubspec('foo', '1.0.0')
    ]).create();

    d.appDir({"foo": {"git": "../foo.git"}}).create();
    pubGet();

    d.git('foo.git', [
      d.libDir('foo'),
      d.libPubspec('foo', '1.0.1')
    ]).commit();

    pubUpgrade();
  });

  integration('reinstalls previously cached git packages', () {
    // Break them.
    List fooDirs;
    schedule(() {
      // Find the cached foo packages for each revision.
      var gitCacheDir = path.join(sandboxDir, cachePath, "git");
      fooDirs = listDir(gitCacheDir)
          .where((dir) => path.basename(dir).startsWith("foo-")).toList();

      // Delete "foo.dart" from them.
      for (var dir in fooDirs) {
        deleteEntry(path.join(dir, "lib", "foo.dart"));
      }
    });

    // Repair them.
    schedulePub(args: ["cache", "repair"],
        output: '''
          Resetting Git repository for foo 1.0.0...
          Resetting Git repository for foo 1.0.1...
          Reinstalled 2 packages.''');

    // The missing libraries should have been replaced.
    schedule(() {
      var fooLibs = fooDirs.map((dir) {
        var fooDirName = path.basename(dir);
        return d.dir(fooDirName, [
          d.dir("lib", [d.file("foo.dart", 'main() => "foo";')])
        ]);
      }).toList();

      d.dir(cachePath, [
        d.dir("git", fooLibs)
      ]).validate();
    });
  });

  integration('deletes packages without pubspecs', () {
    List<String> fooDirs;
    schedule(() {
      var gitCacheDir = path.join(sandboxDir, cachePath, "git");
      fooDirs = listDir(gitCacheDir)
          .where((dir) => path.basename(dir).startsWith("foo-")).toList();

      for (var dir in fooDirs) {
        deleteEntry(path.join(dir, "pubspec.yaml"));
      }
    });

    schedulePub(args: ["cache", "repair"],
        error: allOf([
          contains('Failed to load package:'),
          contains('Could not find a file named "pubspec.yaml" in '),
          contains('foo-'),
        ]),
        output: allOf([
          startsWith('Failed to reinstall 2 packages:'),
          contains('- foo 0.0.0 from git'),
          contains('- foo 0.0.0 from git'),
        ]),
        exitCode: exit_codes.UNAVAILABLE);

    schedule(() {
      d.dir(cachePath, [
        d.dir("git",
            fooDirs.map((dir) => d.nothing(path.basename(dir))))
      ]).validate();
    });
  });

  integration('deletes packages with invalid pubspecs', () {
    List<String> fooDirs;
    schedule(() {
      var gitCacheDir = path.join(sandboxDir, cachePath, "git");
      fooDirs = listDir(gitCacheDir)
          .where((dir) => path.basename(dir).startsWith("foo-")).toList();

      for (var dir in fooDirs) {
        writeTextFile(path.join(dir, "pubspec.yaml"), "{");
      }
    });

    schedulePub(args: ["cache", "repair"],
        error: allOf([
          contains('Failed to load package:'),
          contains('Error on line 1, column 2 of '),
          contains('foo-'),
        ]),
        output: allOf([
          startsWith('Failed to reinstall 2 packages:'),
          contains('- foo 0.0.0 from git'),
          contains('- foo 0.0.0 from git'),
        ]),
        exitCode: exit_codes.UNAVAILABLE);

    schedule(() {
      d.dir(cachePath, [
        d.dir("git",
            fooDirs.map((dir) => d.nothing(path.basename(dir))))
      ]).validate();
    });
  });
}
