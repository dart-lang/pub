// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as path;
import 'package:pub/src/io.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('running pub cache clean when there is no cache', () async {
    final cache = path.join(d.sandbox, cachePath);

    await runPub(args: ['cache', 'clean'], output: 'No pub cache at $cache.');
  });

  test('running pub cache clean --force deletes cache', () async {
    await servePackages()
      ..serve('foo', '1.1.2')
      ..serve('bar', '1.2.3');
    await d.appDir(dependencies: {'foo': 'any', 'bar': 'any'}).create();
    await pubGet();
    final cache = path.join(d.sandbox, cachePath);
    expect(listDir(cache, includeHidden: true), contains(endsWith('hosted')));
    await runPub(
      args: ['cache', 'clean', '--force'],
      output: 'Removing pub cache directory $cache.',
    );

    expect(
      listDir(cache, includeHidden: true),
      // The README.md will be reconstructed.
      [pathInCache('README.md')],
    );
  });

  test('running pub cache clean deletes cache only with confirmation',
      () async {
    await servePackages()
      ..serve('foo', '1.1.2')
      ..serve('bar', '1.2.3');
    await d.appDir(dependencies: {'foo': 'any', 'bar': 'any'}).create();
    await pubGet();
    final cache = path.join(d.sandbox, cachePath);
    expect(
      listDir(cache, includeHidden: true),
      contains(pathInCache('hosted')),
    );
    {
      final process = await startPub(
        args: ['cache', 'clean'],
      );
      process.stdin.writeln('n');
      expect(await process.exitCode, 0);
    }
    expect(
      listDir(cache, includeHidden: true),
      contains(pathInCache('hosted')),
    );

    {
      final process = await startPub(
        args: ['cache', 'clean'],
      );
      process.stdin.writeln('y');
      expect(await process.exitCode, 0);
    }
    expect(
      listDir(
        cache,
        includeHidden: true,
      ), // The README.md will be reconstructed.
      [pathInCache('README.md')],
    );
  });
}
