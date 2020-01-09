// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  setUp(() {
    return servePackages((builder) {
      builder.serve('foo', '1.2.3');
      builder.serve('foo', '1.2.4');
      builder.serve('foo', '1.2.5');
      builder.serve('bar', '1.2.3');
      builder.serve('bar', '1.2.4');
    });
  });

  test('reinstalls previously cached hosted packages', () async {
    // Set up a cache with some broken packages.
    await d.dir(cachePath, [
      d.dir('hosted', [
        d.dir('localhost%58${globalServer.port}', [
          d.dir('foo-1.2.3',
              [d.libPubspec('foo', '1.2.3'), d.file('broken.txt')]),
          d.dir('foo-1.2.5',
              [d.libPubspec('foo', '1.2.5'), d.file('broken.txt')]),
          d.dir(
              'bar-1.2.4', [d.libPubspec('bar', '1.2.4'), d.file('broken.txt')])
        ])
      ])
    ]).create();

    // Repair them.
    await runPub(
        args: ['cache', 'repair'],
        output: '''
          Downloading bar 1.2.4...
          Downloading foo 1.2.3...
          Downloading foo 1.2.5...
          Reinstalled 3 packages.''',
        silent: allOf([
          contains('X-Pub-OS: ${Platform.operatingSystem}'),
          contains('X-Pub-Command: cache repair'),
          contains('X-Pub-Session-ID:'),
          contains('X-Pub-Environment: test-environment'),
          isNot(contains('X-Pub-Reason')),
        ]));

    // The broken versions should have been replaced.
    await d.hostedCache([
      d.dir('bar-1.2.4', [d.nothing('broken.txt')]),
      d.dir('foo-1.2.3', [d.nothing('broken.txt')]),
      d.dir('foo-1.2.5', [d.nothing('broken.txt')])
    ]).validate();
  });

  test('deletes packages without pubspecs', () async {
    // Set up a cache with some broken packages.
    await d.dir(cachePath, [
      d.dir('hosted', [
        d.dir('localhost%58${globalServer.port}', [
          d.dir('bar-1.2.4', [d.file('broken.txt')]),
          d.dir('foo-1.2.3', [d.file('broken.txt')]),
          d.dir('foo-1.2.5', [d.file('broken.txt')]),
        ])
      ])
    ]).create();

    await runPub(
        args: ['cache', 'repair'],
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

    await d.hostedCache([
      d.nothing('bar-1.2.4'),
      d.nothing('foo-1.2.3'),
      d.nothing('foo-1.2.5'),
    ]).validate();
  });

  test('deletes packages with invalid pubspecs', () async {
    // Set up a cache with some broken packages.
    await d.dir(cachePath, [
      d.dir('hosted', [
        d.dir('localhost%58${globalServer.port}', [
          d.dir('bar-1.2.4', [d.file('pubspec.yaml', '{')]),
          d.dir('foo-1.2.3', [d.file('pubspec.yaml', '{')]),
          d.dir('foo-1.2.5', [d.file('pubspec.yaml', '{')]),
        ])
      ])
    ]).create();

    await runPub(
        args: ['cache', 'repair'],
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

    await d.hostedCache([
      d.nothing('bar-1.2.4'),
      d.nothing('foo-1.2.3'),
      d.nothing('foo-1.2.5'),
    ]).validate();
  });
}
