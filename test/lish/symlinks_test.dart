// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tar/tar.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

Future<void> main() async {
  test('symlink directories are replaced by their targets', () async {
    await d.validPackage().create();
    await d.dir('a', [d.file('aa', 'aaa')]).create();
    await d.file('t', 'ttt').create();

    await d.dir(appPath, [
      d.dir('b', [d.file('bb', 'bbb'), d.link('l', p.join(d.sandbox, 't'))]),
      d.link(
        'symlink_to_dir_outside_package',
        p.join(d.sandbox, 'a'),
        forceDirectory: true,
      ),
      d.link(
        'symlink_to_dir_outside_package_relative',
        p.join('..', 'a'),
        forceDirectory: true,
      ),
      d.link(
        'symlink_to_dir_inside_package',
        p.join(d.sandbox, appPath, 'b'),
        forceDirectory: true,
      ),
      d.link(
        'symlink_to_dir_inside_package_relative',
        'b',
        forceDirectory: true,
      ),
    ]).create();

    await runPub(args: ['publish', '--to-archive=archive.tar.gz']);

    final reader = TarReader(
      File(
        p.join(d.sandbox, appPath, 'archive.tar.gz'),
      ).openRead().transform(GZipCodec().decoder),
    );

    while (await reader.moveNext()) {
      final current = reader.current;
      expect(current.type, isNot(TypeFlag.symlink));
    }

    await runPub(args: ['cache', 'preload', 'archive.tar.gz']);

    await d
        .dir('test_pkg-1.0.0', [
          ...d.validPackage().contents,
          d.dir('symlink_to_dir_outside_package', [d.file('aa', 'aaa')]),
          d.dir('symlink_to_dir_outside_package_relative', [
            d.file('aa', 'aaa'),
          ]),
          d.dir('b', [d.file('bb', 'bbb')]),
          d.dir('symlink_to_dir_inside_package', [
            d.file('bb', 'bbb'),
            d.file('l', 'ttt'),
          ]),
          d.dir('symlink_to_dir_inside_package_relative', [
            d.file('bb', 'bbb'),
            d.file('l', 'ttt'),
          ]),
        ])
        .validate(p.join(d.sandbox, cachePath, 'hosted', 'pub.dev'));
  });
}
