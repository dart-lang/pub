// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:pub/src/io.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

main() {
  integration('lists an activated hosted package', () {
    servePackages((builder) {
      builder.serve('foo', '1.0.0');
    });

    schedulePub(args: ['global', 'activate', 'foo']);

    schedulePub(args: ['global', 'list'], output: 'foo 1.0.0');
  });

  integration('lists an activated Git package', () {
    ensureGit();

    d.git('foo.git', [
      d.libPubspec('foo', '1.0.0'),
      d.dir('bin', [d.file('foo.dart', 'main() => print("ok");')])
    ]).create();

    schedulePub(args: ['global', 'activate', '-sgit', '../foo.git']);

    schedulePub(
        args: ['global', 'list'],
        output: 'foo 1.0.0 from Git repository "../foo.git"');
  });

  integration('lists an activated Path package', () {
    d.dir('foo', [
      d.libPubspec('foo', '1.0.0'),
      d.dir('bin', [d.file('foo.dart', 'main() => print("ok");')])
    ]).create();

    schedulePub(args: ['global', 'activate', '-spath', '../foo']);

    var path = canonicalize(p.join(sandboxDir, 'foo'));
    schedulePub(args: ['global', 'list'], output: 'foo 1.0.0 at path "$path"');
  });

  integration('lists activated packages in alphabetical order', () {
    servePackages((builder) {
      builder.serve('aaa', '1.0.0');
      builder.serve('bbb', '1.0.0');
      builder.serve('ccc', '1.0.0');
    });

    schedulePub(args: ['global', 'activate', 'ccc']);
    schedulePub(args: ['global', 'activate', 'aaa']);
    schedulePub(args: ['global', 'activate', 'bbb']);

    schedulePub(
        args: ['global', 'list'],
        output: '''
aaa 1.0.0
bbb 1.0.0
ccc 1.0.0
''');
  });

  integration('lists nothing when no packages activated', () {
    schedulePub(args: ['global', 'list'], output: '\n');
  });
}
