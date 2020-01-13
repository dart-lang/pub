// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:pub/src/io.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('runs a snapshotted script without a .packages file', () async {
    await servePackages((builder) {
      builder.serve('foo', '1.0.0', contents: [
        d.dir('bin', [d.file('script.dart', "main(args) => print('ok');")])
      ]);
    });

    await runPub(args: ['global', 'activate', 'foo']);

    // Mimic the global packages installed by pub <1.12, which didn't create a
    // .packages file for global installs.
    deleteEntry(p.join(d.sandbox, cachePath, 'global_packages/foo/.packages'));

    var pub = await pubRun(global: true, args: ['foo:script']);
    expect(pub.stdout, emits('ok'));
    await pub.shouldExit();
  });

  test('runs an unsnapshotted script without a .packages file', () async {
    await d.dir('foo', [
      d.libPubspec('foo', '1.0.0'),
      d.dir('bin', [d.file('foo.dart', "main() => print('ok');")])
    ]).create();

    await runPub(args: ['global', 'activate', '--source', 'path', '../foo']);

    deleteEntry(p.join(d.sandbox, cachePath, 'global_packages/foo/.packages'));

    var pub = await pubRun(global: true, args: ['foo']);
    expect(pub.stdout, emits('ok'));
    await pub.shouldExit();
  });
}
