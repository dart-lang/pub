// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('does not run pub get with --no-pub', () async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir('bin', [d.file('script.dart', 'main() => print("ok");')]),
      d.packageConfigFile([d.packageConfigEntry(name: 'myapp', path: '.')]),
    ]).create();

    final pub = await pubRun(args: ['--no-pub', 'bin/script']);
    expect(pub.stdout, emitsThrough('ok'));
    expect(pub.stdout, neverEmits('Resolving dependencies...'));
    await pub.shouldExit(0);
  });

  test('fails with --no-pub if package_config.json is missing', () async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir('bin', [d.file('script.dart', 'main() => print("ok");')]),
    ]).create();

    final pub = await pubRun(args: ['--no-pub', 'bin/script']);
    // Pub fails to load the package config.
    expect(
      pub.stderr,
      emitsThrough(
        contains("Cannot open file, path = '.dart_tool/package_config.json'"),
      ),
    );
    await pub.shouldExit(exit_codes.NO_INPUT);
  });

  test('fails with --no-pub if package_config.json is outdated', () async {
    await d.dir(appPath, [
      d.appPubspec(dependencies: {'foo': '1.0.0'}),
      d.dir('bin', [
        d.file('script.dart', 'import "package:foo/foo.dart"; main() {}'),
      ]),
      // Create a package config that doesn't include 'foo'
      d.packageConfigFile([d.packageConfigEntry(name: 'myapp', path: '.')]),
    ]).create();

    final pub = await pubRun(args: ['--no-pub', 'bin/script']);
    // The VM should fail because it can't find the package
    expect(
      pub.stderr,
      emitsThrough(contains("Error: Couldn't resolve the package 'foo'")),
    );
    await pub.shouldExit(1); // Application error (precompilation failed)
  });

  test('runs pub get by default', () async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir('bin', [d.file('script.dart', 'main() => print("ok");')]),
    ]).create();

    final pub = await pubRun(args: ['bin/script']);
    expect(pub.stdout, emitsThrough('Resolving dependencies...'));
    expect(pub.stdout, emitsThrough('ok'));
    await pub.shouldExit(0);
  });

  test('runs pub get with --pub', () async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir('bin', [d.file('script.dart', 'main() => print("ok");')]),
    ]).create();

    final pub = await pubRun(args: ['--pub', 'bin/script']);
    expect(pub.stdout, emitsThrough('Resolving dependencies...'));
    expect(pub.stdout, emitsThrough('ok'));
    await pub.shouldExit(0);
  });
}
