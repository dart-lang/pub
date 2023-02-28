// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('Can use and upgrade git dependency with submodule', () async {
    ensureGit();

    final submodule = d.git(
      'lib.git',
      [d.file('foo.dart', 'main() => print("hi");')],
    );
    await submodule.create();
    final port = await submodule.serve();

    final foo = d.git('foo.git', [d.libPubspec('foo', '1.0.0')]);
    await foo.create();
    await foo.runGit(['submodule', 'add', 'git://localhost:$port/', 'lib']);
    await foo.commit();

    await d.appDir(
      dependencies: {
        'foo': {
          'git': {'url': '../foo.git'}
        }
      },
      contents: [
        d.dir('bin', [d.file('main.dart', 'export "package:foo/foo.dart";')]),
      ],
    ).create();
    await pubGet();

    await runPub(args: ['run', 'myapp:main'], output: contains('hi'));

    await d.git(
      'lib.git',
      [d.file('foo.dart', 'main() => print("bye");')],
    ).commit();

    await foo.runGit(['submodule', 'update', '--remote', '--merge']);
    await foo.commit();

    await pubUpgrade();
    await runPub(args: ['run', 'myapp:main'], output: contains('bye'));
  });

  test('Can use LFS', () async {
    ensureGit();

    final foo = d.git('foo.git', [d.libPubspec('foo', '1.0.0')]);
    await foo.create();
    await foo.runGit(['lfs', 'install']);

    await d.dir('foo.git', [
      d.dir('lib', [d.file('foo.dart', 'main() => print("hello");')])
    ]).create();
    await foo.runGit(['lfs', 'track', 'lib/foo.dart']);
    await foo.runGit(['add', '.gitattributes']);
    await foo.commit();

    await d.appDir(
      dependencies: {
        'foo': {
          'git': {'url': '../foo.git'}
        }
      },
      contents: [
        d.dir('bin', [d.file('main.dart', 'export "package:foo/foo.dart";')]),
      ],
    ).create();
    await pubGet();

    await runPub(args: ['run', 'myapp:main'], output: contains('hi'));

    await d.git(
      'foo.git',
      [
        d.dir('lib', [d.file('foo.dart', 'main() => print("bye");')])
      ],
    ).commit();

    await pubUpgrade();
    await runPub(args: ['run', 'myapp:main'], output: contains('bye'));
  });
}
