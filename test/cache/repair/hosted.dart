// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:scheduled_test/scheduled_test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

main() {
  setUp(() {
    servePackages((builder) {
      builder.serve("foo", "1.2.3");
      builder.serve("foo", "1.2.4");
      builder.serve("foo", "1.2.5");
      builder.serve("bar", "1.2.3");
      builder.serve("bar", "1.2.4");
    });
  });

  integration('reinstalls previously cached hosted packages', () {
    // Set up a cache with some broken packages.
    d.dir(cachePath, [
      d.dir('hosted', [
        d.async(globalServer.port.then((p) => d.dir('localhost%58$p', [
          d.dir("foo-1.2.3", [
            d.libPubspec("foo", "1.2.3"),
            d.file("broken.txt")
          ]),
          d.dir("foo-1.2.5", [
            d.libPubspec("foo", "1.2.5"),
            d.file("broken.txt")
          ]),
          d.dir("bar-1.2.4", [
            d.libPubspec("bar", "1.2.4"),
            d.file("broken.txt")
          ])
        ])))
      ])
    ]).create();

    // Repair them.
    schedulePub(args: ["cache", "repair"],
        output: '''
          Downloading bar 1.2.4...
          Downloading foo 1.2.3...
          Downloading foo 1.2.5...
          Reinstalled 3 packages.''');

    // The broken versions should have been replaced.
    d.hostedCache([
      d.dir("bar-1.2.4", [d.nothing("broken.txt")]),
      d.dir("foo-1.2.3", [d.nothing("broken.txt")]),
      d.dir("foo-1.2.5", [d.nothing("broken.txt")])
    ]).validate();
  });

  integration('deletes packages without pubspecs', () {
    // Set up a cache with some broken packages.
    d.dir(cachePath, [
      d.dir('hosted', [
        d.async(globalServer.port.then((p) => d.dir('localhost%58$p', [
          d.dir("bar-1.2.4", [d.file("broken.txt")]),
          d.dir("foo-1.2.3", [d.file("broken.txt")]),
          d.dir("foo-1.2.5", [d.file("broken.txt")]),
        ])))
      ])
    ]).create();

    schedulePub(args: ["cache", "repair"],
        error: allOf([
          contains('Failed to load package:'),
          contains('Could not find a file named "pubspec.yaml" in '),
          contains('bar-1.2.4'),
          contains('foo-1.2.3'),
          contains('foo-1.2.5'),
        ]),
        output: allOf([
          startsWith('Failed to reinstall 3 packages:'),
          contains('- bar 1.2.4'),
          contains('- foo 1.2.3'),
          contains('- foo 1.2.5'),
        ]),
        exitCode: exit_codes.UNAVAILABLE);

    d.hostedCache([
      d.nothing("bar-1.2.4"),
      d.nothing("foo-1.2.3"),
      d.nothing("foo-1.2.5"),
    ]).validate();
  });

  integration('deletes packages with invalid pubspecs', () {
    // Set up a cache with some broken packages.
    d.dir(cachePath, [
      d.dir('hosted', [
        d.async(globalServer.port.then((p) => d.dir('localhost%58$p', [
          d.dir("bar-1.2.4", [d.file("pubspec.yaml", "{")]),
          d.dir("foo-1.2.3", [d.file("pubspec.yaml", "{")]),
          d.dir("foo-1.2.5", [d.file("pubspec.yaml", "{")]),
        ])))
      ])
    ]).create();

    schedulePub(args: ["cache", "repair"],
        error: allOf([
          contains('Failed to load package:'),
          contains('Error on line 1, column 2 of '),
          contains('bar-1.2.4'),
          contains('foo-1.2.3'),
          contains('foo-1.2.5'),
        ]),
        output: allOf([
          startsWith('Failed to reinstall 3 packages:'),
          contains('- bar 1.2.4'),
          contains('- foo 1.2.3'),
          contains('- foo 1.2.5'),
        ]),
        exitCode: exit_codes.UNAVAILABLE);

    d.hostedCache([
      d.nothing("bar-1.2.4"),
      d.nothing("foo-1.2.3"),
      d.nothing("foo-1.2.5"),
    ]).validate();
  });
}
