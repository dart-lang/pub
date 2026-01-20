// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  setUp(() async {
    await servePackages()
      ..serve('foo', '1.2.3')
      ..serve('foo', '1.2.4')
      ..serve('foo', '1.2.5')
      ..serve('bar', '1.2.3')
      ..serve('bar', '1.2.4');
  });

  test('repairs only packages from pubspec.lock by default', () async {
    // Create a project with foo dependency.
    await d.appDir(dependencies: {'foo': '1.2.3'}).create();
    await pubGet();

    // Set up a cache with some broken packages (including bar which is not in
    // the project's dependencies).
    await d.dir(cachePath, [
      d.dir('hosted', [
        d.dir('localhost%58${globalServer.port}', [
          d.dir('foo-1.2.3', [
            d.libPubspec('foo', '1.2.3'),
            d.file('broken.txt'),
          ]),
          d.dir('bar-1.2.4', [
            d.libPubspec('bar', '1.2.4'),
            d.file('broken.txt'),
          ]),
        ]),
      ]),
    ]).create();

    // Repair without --all should only repair foo (from pubspec.lock).
    await runPub(args: ['cache', 'repair'], output: 'Reinstalled 1 package.');

    // foo should be repaired, bar should still have broken.txt.
    await d.hostedCache([
      d.dir('foo-1.2.3', [d.nothing('broken.txt')]),
      d.dir('bar-1.2.4', [d.file('broken.txt')]),
    ]).validate();
  });

  test('repairs only the specific version from pubspec.lock', () async {
    // Create a project with foo 1.2.3 dependency.
    await d.appDir(dependencies: {'foo': '1.2.3'}).create();
    await pubGet();

    // Set up a cache with multiple versions of foo (both broken).
    await d.dir(cachePath, [
      d.dir('hosted', [
        d.dir('localhost%58${globalServer.port}', [
          d.dir('foo-1.2.3', [
            d.libPubspec('foo', '1.2.3'),
            d.file('broken.txt'),
          ]),
          d.dir('foo-1.2.5', [
            d.libPubspec('foo', '1.2.5'),
            d.file('broken.txt'),
          ]),
        ]),
      ]),
    ]).create();

    // Repair without --all should only repair foo 1.2.3.
    await runPub(args: ['cache', 'repair'], output: 'Reinstalled 1 package.');

    // Only foo 1.2.3 should be repaired, foo 1.2.5 should still be broken.
    await d.hostedCache([
      d.dir('foo-1.2.3', [d.nothing('broken.txt')]),
      d.dir('foo-1.2.5', [d.file('broken.txt')]),
    ]).validate();
  });

  test('handles missing pubspec.lock', () async {
    await d.appDir().create();
    // Don't run pub get, so there's no pubspec.lock

    await runPub(
      args: ['cache', 'repair'],
      output: contains('No pubspec.lock found'),
    );
  });

  test('does not repair cached packages for path dependencies', () async {
    // Create foo as a path dependency.
    await d.dir('foo', [d.libPubspec('foo', '1.0.0')]).create();
    await d
        .appDir(
          dependencies: {
            'foo': {'path': '../foo'},
          },
        )
        .create();
    await pubGet();

    // Set up a broken cached version of foo (same name, but different source).
    await d.dir(cachePath, [
      d.dir('hosted', [
        d.dir('localhost%58${globalServer.port}', [
          d.dir('foo-1.2.3', [
            d.libPubspec('foo', '1.2.3'),
            d.file('broken.txt'),
          ]),
        ]),
      ]),
    ]).create();

    // Repair without --all should NOT repair foo-1.2.3 because the project's
    // foo dependency is a path dep, not a hosted dep.
    await runPub(
      args: ['cache', 'repair'],
      output: 'No packages from pubspec.lock found in cache.',
    );

    // foo-1.2.3 should still have broken.txt.
    await d.hostedCache([
      d.dir('foo-1.2.3', [d.file('broken.txt')]),
    ]).validate();
  });

  test('git dep does not repair same-named hosted package', () async {
    // Create foo as a git dependency.
    await d.git('foo.git', [
      d.libDir('foo'),
      d.libPubspec('foo', '1.0.0'),
    ]).create();

    await d
        .appDir(
          dependencies: {
            'foo': {'git': '../foo.git'},
          },
        )
        .create();
    await pubGet();

    // Set up a broken cached hosted version of foo (same name, but hosted).
    await d.dir(cachePath, [
      d.dir('hosted', [
        d.dir('localhost%58${globalServer.port}', [
          d.dir('foo-1.2.3', [
            d.libPubspec('foo', '1.2.3'),
            d.file('broken.txt'),
          ]),
        ]),
      ]),
    ]).create();

    // Repair without --all should NOT repair hosted foo-1.2.3 because the
    // project's foo dependency is a git dep, not a hosted dep.
    await runPub(
      args: ['cache', 'repair'],
      output: contains('Reinstalled 1 package'),
    );

    // hosted foo-1.2.3 should still have broken.txt.
    await d.hostedCache([
      d.dir('foo-1.2.3', [d.file('broken.txt')]),
    ]).validate();
  });

  test('reinstalls previously cached hosted packages', () async {
    // Set up a cache with some broken packages.
    await d.dir(cachePath, [
      d.dir('hosted', [
        d.dir('localhost%58${globalServer.port}', [
          d.dir('foo-1.2.3', [
            d.libPubspec('foo', '1.2.3'),
            d.file('broken.txt'),
          ]),
          d.dir('foo-1.2.5', [
            d.libPubspec('foo', '1.2.5'),
            d.file('broken.txt'),
          ]),
          d.dir('bar-1.2.4', [
            d.libPubspec('bar', '1.2.4'),
            d.file('broken.txt'),
          ]),
        ]),
      ]),
    ]).create();

    // Repair them.
    await runPub(
      args: ['cache', 'repair', '--all'],
      output: 'Reinstalled 3 packages.',
      silent: allOf([
        contains('Downloading bar 1.2.4...'),
        contains('Downloading foo 1.2.3...'),
        contains('Downloading foo 1.2.5...'),
        contains('X-Pub-OS: ${Platform.operatingSystem}'),
        contains('X-Pub-Command: cache repair'),
        contains('X-Pub-Session-ID:'),
        contains('X-Pub-Environment: test-environment'),
        isNot(contains('X-Pub-Reason')),
      ]),
    );

    // The broken versions should have been replaced.
    await d.hostedCache([
      d.dir('bar-1.2.4', [d.nothing('broken.txt')]),
      d.dir('foo-1.2.3', [d.nothing('broken.txt')]),
      d.dir('foo-1.2.5', [d.nothing('broken.txt')]),
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
        ]),
      ]),
    ]).create();

    await runPub(
      args: ['cache', 'repair', '--all'],
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
      exitCode: exit_codes.UNAVAILABLE,
    );

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
        ]),
      ]),
    ]).create();

    await runPub(
      args: ['cache', 'repair', '--all'],
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
      exitCode: exit_codes.UNAVAILABLE,
    );

    await d.hostedCache([
      d.nothing('bar-1.2.4'),
      d.nothing('foo-1.2.3'),
      d.nothing('foo-1.2.5'),
    ]).validate();
  });
}
