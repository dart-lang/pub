// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:pub/src/io.dart';
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('Report retracted packages', () async {
    final server = await servePackages()
      ..serve('foo', '1.0.0', deps: {'bar': 'any'})
      ..serve('bar', '1.0.0');
    await d.appDir(dependencies: {'foo': '1.0.0'}).create();

    await pubGet();

    server.retractPackageVersion('bar', '1.0.0');
    // Delete the cache to trigger the report.
    final barVersionsCache =
        p.join(server.cachingPath, '.cache', 'bar-versions.json');
    expect(fileExists(barVersionsCache), isTrue);
    deleteEntry(barVersionsCache);
    await pubGet(output: contains('bar 1.0.0 (retracted)'));
  });

  test('Report retracted packages with newer version available', () async {
    final server = await servePackages()
      ..serve('foo', '1.0.0', deps: {'bar': '^1.0.0'})
      ..serve('bar', '1.0.0')
      ..serve('bar', '2.0.0')
      ..serve('bar', '2.0.1-pre');
    await d.appDir(dependencies: {'foo': '1.0.0'}).create();

    await pubGet();

    server.retractPackageVersion('bar', '1.0.0');
    // Delete the cache to trigger the report.
    final barVersionsCache =
        p.join(server.cachingPath, '.cache', 'bar-versions.json');
    expect(fileExists(barVersionsCache), isTrue);
    deleteEntry(barVersionsCache);
    await pubGet(output: contains('bar 1.0.0 (retracted, 2.0.0 available)'));
  });

  test('Report retracted packages with newer prerelease version available',
      () async {
    final server = await servePackages()
      ..serve('foo', '1.0.0', deps: {'bar': '^1.0.0-pre'})
      ..serve('bar', '1.0.0-pre')
      ..serve('bar', '2.0.1-pre');
    await d.appDir(dependencies: {'foo': '1.0.0'}).create();

    await pubGet();

    server.retractPackageVersion('bar', '1.0.0-pre');
    // Delete the cache to trigger the report.
    final barVersionsCache =
        p.join(server.cachingPath, '.cache', 'bar-versions.json');
    expect(fileExists(barVersionsCache), isTrue);
    deleteEntry(barVersionsCache);
    await pubGet(
      output: contains('bar 1.0.0-pre (retracted, 2.0.1-pre available)'),
    );
  });
}
