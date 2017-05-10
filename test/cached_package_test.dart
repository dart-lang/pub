// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:scheduled_test/scheduled_test.dart';

import 'package:pub/src/cached_package.dart';
import 'package:pub/src/package.dart';
import 'package:pub/src/pubspec.dart';

import 'descriptor.dart' as d;
import 'test_pub.dart';

main() {
  group('CachedPackage', () {
    CachedPackage cachedPackage;

    setUpCachedPackage() {
      d.dir('cache', [
        d.dir('app', [
          d.dir('lib', [
            d.file('cached.txt', 'hello'),
            d.file('original.txt', 'world'),
          ]),
        ]),
      ]).create();
      d.dir('app', [
        d.dir('lib', [
          d.file('original.txt'),
        ])
      ]).create();

      cachedPackage = new CachedPackage(
          new Package(new Pubspec('a'), p.join(d.defaultRoot, 'app')),
          p.join(d.defaultRoot, 'cache', 'app'));
    }

    // Regression test for https://github.com/dart-lang/pub/issues/1586.
    integration('Can list the cached lib dir and compute relative paths', () {
      setUpCachedPackage();
      schedule(() {
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
    });

    integration('Cannot list files outside of lib', () {
      setUpCachedPackage();
      schedule(() {
        expect(() => cachedPackage.listFiles(), throwsUnsupportedError);
        expect(() => cachedPackage.listFiles(beneath: 'bin'),
            throwsUnsupportedError);
        expect(cachedPackage.listFiles(beneath: 'lib'), isNotNull);
      });
    });
  });
}
