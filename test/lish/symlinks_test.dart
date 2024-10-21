// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tar/tar.dart';
import 'package:test/test.dart';

import '../descriptor.dart';
import '../test_pub.dart';

Future<void> main() async {
  test('symlink directories are replaced by their targets', () async {
    await validPackage().create();
    await dir('a', [file('aa', 'aaa')]).create();
    await file('t', 'ttt').create();

    await dir(appPath, [
      dir('b', [file('bb', 'bbb')]),
    ]).create();
    Link(p.join(sandbox, appPath, 'symlink_to_dir_outside_package'))
        .createSync(p.join(sandbox, 'a'));
    Link(p.join(sandbox, appPath, 'symlink_to_dir_outside_package_relative'))
        .createSync(p.join('..', 'a'));
    Link(p.join(sandbox, appPath, 'symlink_to_dir_inside_package'))
        .createSync(p.join(sandbox, appPath, 'b'));
    Link(p.join(sandbox, appPath, 'symlink_to_dir_inside_package_relative'))
        .createSync('b');
    Link(p.join(sandbox, appPath, 'b', 'l')).createSync(p.join(sandbox, 't'));

    await runPub(args: ['publish', '--to-archive=archive.tar.gz']);

    final reader = TarReader(
      File(p.join(sandbox, appPath, 'archive.tar.gz'))
          .openRead()
          .transform(GZipCodec().decoder),
    );

    while (await reader.moveNext()) {
      final current = reader.current;
      expect(current.type, isNot(TypeFlag.symlink));
    }

    await runPub(args: ['cache', 'preload', 'archive.tar.gz']);

    await dir('test_pkg-1.0.0', [
      ...validPackage().contents,
      dir('symlink_to_dir_outside_package', [
        file('aa', 'aaa'),
      ]),
      dir('symlink_to_dir_outside_package_relative', [
        file('aa', 'aaa'),
      ]),
      dir('b', [file('bb', 'bbb')]),
      dir('symlink_to_dir_inside_package', [
        file('bb', 'bbb'),
        file('l', 'ttt'),
      ]),
      dir('symlink_to_dir_inside_package_relative', [
        file('bb', 'bbb'),
        file('l', 'ttt'),
      ]),
    ]).validate(
      p.join(sandbox, cachePath, 'hosted', 'pub.dev'),
    );
  });
}
