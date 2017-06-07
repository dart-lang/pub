// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:pub/src/cached_package.dart';
import 'package:pub/src/package.dart';
import 'package:pub/src/pubspec.dart';

import 'descriptor.dart' as d;

main() {
  // Regression test for https://github.com/dart-lang/pub/issues/1586.
  test('Can list the cached lib dir and compute relative paths', () async {
    await d.dir('cache', [
      d.dir('app', [
        d.dir('lib', [
          d.file('cached.txt', 'hello'),
          d.file('original.txt', 'world'),
        ]),
      ]),
    ]).create();

    await d.dir('app', [
      d.dir('lib', [
        d.file('original.txt'),
      ])
    ]).create();

    var cachedPackage = new CachedPackage(
        new Package(new Pubspec('a'), p.join(d.sandbox, 'app')),
        p.join(d.sandbox, 'cache', 'app'));

    var paths = cachedPackage.listFiles(beneath: 'lib');
    expect(
        paths,
        unorderedMatches([
          endsWith('cached.txt'),
          endsWith('original.txt'),
        ]));
    for (var path in paths) {
      expect(cachedPackage.relative(path), startsWith('lib'));
    }
  });
}
