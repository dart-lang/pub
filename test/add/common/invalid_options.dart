// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('cannot use both --path and --git-<option> flags', () async {
    ensureGit();

    await d.git(
        'foo.git', [d.libDir('foo'), d.libPubspec('foo', '1.0.0')]).create();
    await d
        .dir('bar', [d.libDir('bar'), d.libPubspec('foo', '0.0.1')]).create();

    await d.appDir({}).create();

    await pubAdd(
        args: ['foo', '--git-url', '../foo.git', '--path', '../bar'],
        error: allOf([
          contains('Packages can only have one source, pub add flags '
              '"--git-url" and "--path" are'),
          contains('conflicting.')
        ]),
        exitCode: exit_codes.USAGE);

    await d.appDir({}).validate();
    await d.dir(appPath, [
      d.nothing('.dart_tool/package_config.json'),
      d.nothing('pubspec.lock'),
      d.nothing('.packages'),
    ]).validate();
  });

  test('cannot use both --path and --host-<option> flags', () async {
    // Make the default server serve errors. Only the custom server should
    // be accessed.
    await serveErrors();

    final server = await PackageServer.start((builder) {
      builder.serve('foo', '1.2.3');
    });

    await d
        .dir('bar', [d.libDir('bar'), d.libPubspec('foo', '0.0.1')]).create();
    await d.appDir({}).create();

    await pubAdd(
        args: [
          'foo',
          '--hosted-url',
          'http://localhost:${server.port}',
          '--path',
          '../bar'
        ],
        error: allOf([
          contains('Packages can only have one source, pub add flags '
              '"--hosted-url" and "--path" are'),
          contains('conflicting.')
        ]),
        exitCode: exit_codes.USAGE);

    await d.appDir({}).validate();
    await d.dir(appPath, [
      d.nothing('.dart_tool/package_config.json'),
      d.nothing('pubspec.lock'),
      d.nothing('.packages'),
    ]).validate();
  });

  test('cannot use both --hosted-url and --git-<option> flags', () async {
    // Make the default server serve errors. Only the custom server should
    // be accessed.
    await serveErrors();

    final server = await PackageServer.start((builder) {
      builder.serve('foo', '1.2.3');
    });

    ensureGit();

    await d.git(
        'foo.git', [d.libDir('foo'), d.libPubspec('foo', '1.0.0')]).create();
    await d.appDir({}).create();

    await pubAdd(
        args: [
          'foo',
          '--hosted-url',
          'http://localhost:${server.port}',
          '--git-url',
          '../foo.git'
        ],
        error: allOf([
          contains('Packages can only have one source, pub add flags '
              '"--git-url" and "--hosted-url"'),
          contains('are conflicting.')
        ]),
        exitCode: exit_codes.USAGE);

    await d.appDir({}).validate();
    await d.dir(appPath, [
      d.nothing('.dart_tool/package_config.json'),
      d.nothing('pubspec.lock'),
      d.nothing('.packages'),
    ]).validate();
  });
}
