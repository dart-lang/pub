// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:pub/src/io.dart';
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('activating a hosted package deactivates the path one', () async {
    await servePackages((builder) {
      builder.serve('foo', '1.0.0', contents: [
        d.dir('bin', [d.file('foo.dart', "main(args) => print('hosted');")])
      ]);
    });

    await d.dir('foo', [
      d.libPubspec('foo', '2.0.0'),
      d.dir('bin', [d.file('foo.dart', "main() => print('path');")])
    ]).create();

    await runPub(args: ['global', 'activate', 'foo']);

    var path = canonicalize(p.join(d.sandbox, 'foo'));
    await runPub(
        args: ['global', 'activate', '-spath', '../foo'],
        output: allOf([
          contains('Package foo is currently active at version 1.0.0.'),
          contains('Activated foo 2.0.0 at path "$path".')
        ]));

    // Should now run the path one.
    var pub = await pubRun(global: true, args: ['foo']);
    expect(pub.stdout, emits('path'));
    await pub.shouldExit();
  });
}
