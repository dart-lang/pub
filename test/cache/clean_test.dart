// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/io.dart';
import 'package:test/test.dart';

import 'package:path/path.dart' as path;

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('running pub cache clean when there is no cache', () async {
    final cache = path.join(d.sandbox, cachePath);

    await runPub(args: ['cache', 'clean'], output: 'No pub cache at $cache.');
  });

  test('running pub cache clean deletes cache', () async {
    await servePackages((b) => b..serve('foo', '1.1.2')..serve('bar', '1.2.3'));
    await d.appDir({'foo': 'any', 'bar': 'any'}).create();
    await pubGet();
    final cache = path.join(d.sandbox, cachePath);
    expect(dirExists(cache), isTrue);
    await runPub(
        args: ['cache', 'clean'],
        output: 'Removing pub cache directory $cache.');
    expect(dirExists(cache), isFalse);
  });
}
