// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import 'package:pub/src/io.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('--dry-run: shows report, changes nothing', () async {
    await servePackages((builder) {
      builder.serve('foo', '1.0.0');
      builder.serve('foo', '2.0.0');
    });

    // Create the first lockfile.
    await d.appDir({'foo': '1.0.0'}).create();

    await pubGet();

    await d.dir(appPath, [
      d.file('pubspec.lock', contains('1.0.0')),
      d.dir('.dart_tool'),
    ]).validate();

    // Change the pubspec.
    await d.appDir({'foo': 'any'}).create();

    // Also delete the ".dart_tool" directory.
    deleteEntry(path.join(d.sandbox, appPath, '.dart_tool'));

    // Do the dry run.
    await pubUpgrade(
      args: ['--dry-run'],
      output: allOf([
        contains('> foo 2.0.0 (was 1.0.0)'),
        contains('Would change 1 dependency.'),
      ]),
    );

    await d.dir(appPath, [
      // The lockfile should be unmodified.
      d.file('pubspec.lock', contains('1.0.0')),
      // The ".dart_tool" directory should not have been regenerated.
      d.nothing('.dart_tool')
    ]).validate();
  });

  test('--dry-run --major-versions: shows report, changes nothing', () async {
    await servePackages((builder) {
      builder.serve('foo', '1.0.0');
      builder.serve('foo', '2.0.0');
    });

    await d.appDir({'foo': '^1.0.0'}).create();

    await pubGet();

    await d.dir(appPath, [
      d.file('pubspec.lock', contains('1.0.0')),
      d.dir('.dart_tool'),
    ]).validate();

    // Also delete the ".dart_tool" directory.
    deleteEntry(path.join(d.sandbox, appPath, '.dart_tool'));

    // Do the dry run.
    await pubUpgrade(
      args: ['--dry-run', '--major-versions'],
      output: allOf([
        contains('Resolving dependencies...'),
        contains('> foo 2.0.0 (was 1.0.0)'),
        contains('Would change 1 dependency.'),
        contains('Would change 1 constraint in pubspec.yaml:'),
        contains('foo: ^1.0.0 -> ^2.0.0'),
      ]),
    );

    await d.dir(appPath, [
      // The pubspec should not be modified.
      d.appPubspec({'foo': '^1.0.0'}),
      // The lockfile should not be modified.
      d.file('pubspec.lock', contains('1.0.0')),
      // The ".dart_tool" directory should not have been regenerated.
      d.nothing('.dart_tool')
    ]).validate();

    // Try without --dry-run
    await pubUpgrade(
      args: ['--major-versions'],
      output: allOf([
        contains('Resolving dependencies...'),
        contains('> foo 2.0.0 (was 1.0.0)'),
        contains('Downloading foo 2.0.0...'),
        contains('Changed 1 dependency!'),
        contains('Changed 1 constraint in pubspec.yaml:'),
        contains('foo: ^1.0.0 -> ^2.0.0'),
      ]),
    );

    await d.dir(appPath, [
      d.appPubspec({'foo': '^2.0.0'}),
      d.file('pubspec.lock', contains('2.0.0')),
      d.dir('.dart_tool')
    ]).validate();
  });
}
