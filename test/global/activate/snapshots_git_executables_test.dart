// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('snapshots the executables for a Git repo', () async {
    ensureGit();

    await d.git('foo.git', [
      d.libPubspec('foo', '1.0.0'),
      d.dir('bin', [
        d.file('hello.dart', "void main() => print('hello!');"),
        d.file('goodbye.dart', "void main() => print('goodbye!');"),
        d.file('shell.sh', 'echo shell'),
        d.dir('subdir', [d.file('sub.dart', "void main() => print('sub!');")])
      ])
    ]).create();

    await runPub(
        args: ['global', 'activate', '-sgit', '../foo.git'],
        output: allOf([
          contains('Precompiled foo:hello.'),
          contains('Precompiled foo:goodbye.')
        ]));

    await d.dir(cachePath, [
      d.dir('global_packages', [
        d.dir('foo', [
          d.file('pubspec.lock', contains('1.0.0')),
          d.dir('bin', [
            d.file('hello.dart.snapshot.dart2', contains('hello!')),
            d.file('goodbye.dart.snapshot.dart2', contains('goodbye!')),
            d.nothing('shell.sh.snapshot.dart2'),
            d.nothing('subdir')
          ])
        ])
      ])
    ]).validate();
  });
}
