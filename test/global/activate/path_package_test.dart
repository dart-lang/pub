// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:pub/src/io.dart';
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('activates a package at a local path', () async {
    await d.dir('foo', [
      d.libPubspec('foo', '1.0.0'),
      d.dir('bin', [d.file('foo.dart', "main() => print('ok');")]),
    ]).create();

    final path = canonicalize(p.join(d.sandbox, 'foo'));
    await runPub(
      args: ['global', 'activate', '--source', 'path', '../foo'],
      output: endsWith('Activated foo 1.0.0 at path "$path".'),
    );
  });

  // Regression test for #1751
  test(
    'activates a package at a local path with a relative path dependency',
    () async {
      await d.dir('foo', [
        d.libPubspec(
          'foo',
          '1.0.0',
          deps: {
            'bar': {'path': '../bar'},
          },
        ),
        d.dir('bin', [
          d.file('foo.dart', """
        import 'package:bar/bar.dart';

        main() => print(value);
      """),
        ]),
      ]).create();

      await d.dir('bar', [
        d.libPubspec('bar', '1.0.0'),
        d.dir('lib', [d.file('bar.dart', "final value = 'ok';")]),
      ]).create();

      final path = canonicalize(p.join(d.sandbox, 'foo'));
      await runPub(
        args: ['global', 'activate', '--source', 'path', '../foo'],
        output: endsWith('Activated foo 1.0.0 at path "$path".'),
      );

      await runPub(
        args: ['global', 'run', 'foo'],
        output: endsWith('ok'),
        workingDirectory: p.current,
      );
    },
  );

  test("Doesn't precompile binaries when activating from path", () async {
    final server = await servePackages();
    server.serve(
      'bar',
      '1.0.0',
      contents: [
        d.dir('bin', [d.file('bar.dart', "main() => print('bar');")]),
      ],
    );

    await d.dir('foo', [
      d.libPubspec('foo', '1.0.0', deps: {'bar': '^1.0.0'}),
      d.dir('bin', [d.file('foo.dart', "main() => print('ok');")]),
    ]).create();

    await runPub(
      args: ['global', 'activate', '--source', 'path', '../foo'],
      output: allOf([
        contains('Activated foo 1.0.0 at path'),
        isNot(contains('Built')),
      ]),
    );
  });
}
