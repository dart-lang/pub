// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:path/path.dart' as p;
import 'package:pub/src/io.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('lists an activated hosted package', () async {
    await servePackages((builder) {
      builder.serve('foo', '1.0.0');
    });

    await runPub(args: ['global', 'activate', 'foo']);

    await runPub(args: ['global', 'list'], output: 'foo 1.0.0');
  });

  test('lists an activated Git package', () async {
    ensureGit();

    await d.git('foo.git', [
      d.libPubspec('foo', '1.0.0'),
      d.dir('bin', [d.file('foo.dart', 'main() => print("ok");')])
    ]).create();

    await runPub(args: ['global', 'activate', '-sgit', '../foo.git']);

    await runPub(
        args: ['global', 'list'],
        output: 'foo 1.0.0 from Git repository "../foo.git"');
  });

  test('lists an activated Path package', () async {
    await d.dir('foo', [
      d.libPubspec('foo', '1.0.0'),
      d.dir('bin', [d.file('foo.dart', 'main() => print("ok");')])
    ]).create();

    await runPub(args: ['global', 'activate', '-spath', '../foo']);

    var path = canonicalize(p.join(d.sandbox, 'foo'));
    await runPub(args: ['global', 'list'], output: 'foo 1.0.0 at path "$path"');
  });

  test('lists activated packages in alphabetical order', () async {
    await servePackages((builder) {
      builder.serve('aaa', '1.0.0');
      builder.serve('bbb', '1.0.0');
      builder.serve('ccc', '1.0.0');
    });

    await runPub(args: ['global', 'activate', 'ccc']);
    await runPub(args: ['global', 'activate', 'aaa']);
    await runPub(args: ['global', 'activate', 'bbb']);

    await runPub(args: ['global', 'list'], output: '''
aaa 1.0.0
bbb 1.0.0
ccc 1.0.0
''');
  });

  test('lists nothing when no packages activated', () async {
    await runPub(args: ['global', 'list'], output: '\n');
  });
}
