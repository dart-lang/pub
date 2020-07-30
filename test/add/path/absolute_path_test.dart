// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as path;
import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('path dependency with absolute path', () async {
    await d
        .dir('foo', [d.libDir('foo'), d.libPubspec('foo', '0.0.1')]).create();

    await d.appDir({}).create();

    final absolutePath = path.join(d.sandbox, 'foo');

    await pubAdd(args: ['foo', '--path', absolutePath]);

    await d.appPackagesFile({'foo': absolutePath}).validate();

    await d.appDir({
      'foo': {'path': absolutePath}
    }).validate();
  });

  test('fails if path does not exist', () async {
    await d.appDir({}).create();

    final absolutePath = path.join(d.sandbox, 'foo');

    await pubAdd(
        args: ['foo', '--path', absolutePath],
        error: contains(
            'Because myapp depends on foo from path which doesn\'t exist '
            '(could not find package foo at "$absolutePath"), version solving '
            'failed.'),
        exitCode: exit_codes.NO_INPUT);
  });

  test('can be overriden by dependency override', () async {
    await servePackages((builder) {
      builder.serve('foo', '1.2.2');
    });
    await d
        .dir('foo', [d.libDir('foo'), d.libPubspec('foo', '0.0.1')]).create();

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependencies': {},
        'dependency_overrides': {'foo': '1.2.2'}
      })
    ]).create();

    final absolutePath = path.join(d.sandbox, 'foo');
    await pubAdd(args: ['foo', '--path', absolutePath]);

    await d.cacheDir({'foo': '1.2.2'}).validate();
    await d.appPackagesFile({'foo': '1.2.2'}).validate();
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependencies': {
          'foo': {'path': absolutePath}
        },
        'dependency_overrides': {'foo': '1.2.2'}
      })
    ]).validate();
  });
}
