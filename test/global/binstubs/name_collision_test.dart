// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('does not overwrite an existing binstub', () async {
    await d.dir('foo', [
      d.pubspec({
        'name': 'foo',
        'executables': {'foo': 'foo', 'collide1': 'foo', 'collide2': 'foo'}
      }),
      d.dir('bin', [d.file('foo.dart', "main() => print('ok');")])
    ]).create();

    await d.dir('bar', [
      d.pubspec({
        'name': 'bar',
        'executables': {'bar': 'bar', 'collide1': 'bar', 'collide2': 'bar'}
      }),
      d.dir('bin', [d.file('bar.dart', "main() => print('ok');")])
    ]).create();

    await runPub(args: ['global', 'activate', '-spath', '../foo']);

    var pub = await startPub(args: ['global', 'activate', '-spath', '../bar']);
    expect(pub.stdout, emitsThrough('Installed executable bar.'));
    expect(pub.stderr,
        emits('Executable collide1 was already installed from foo.'));
    expect(pub.stderr,
        emits('Executable collide2 was already installed from foo.'));
    expect(
        pub.stderr,
        emits('Deactivate the other package(s) or activate bar using '
            '--overwrite.'));
    await pub.shouldExit();

    await d.dir(cachePath, [
      d.dir('bin', [
        d.file(binStubName('foo'), contains('foo:foo')),
        d.file(binStubName('bar'), contains('bar:bar')),
        d.file(binStubName('collide1'), contains('foo:foo')),
        d.file(binStubName('collide2'), contains('foo:foo'))
      ])
    ]).validate();
  });
}
