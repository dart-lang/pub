// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:pub/src/io.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('Warns about discontinued packages', () async {
    await servePackages((builder) => builder.serve('foo', '1.2.3'));
    await d.appDir({'foo': '1.2.3'}).create();
    await pubGet();

    globalPackageServer.add((builder) => builder.discontinue('foo'));
    // A pub get straight away will not trigger the warning, as we cache
    // responses for a while.
    await pubGet();
    final versionsCache = p.join(d.sandbox, cachePath, 'hosted',
        'localhost%58${globalServer.port}', 'foo-versions.json');
    expect(fileExists(versionsCache), isTrue);
    deleteEntry(versionsCache);
    await pubGet(warning: 'Package:foo has been discontinued.');
    expect(fileExists(versionsCache), isTrue);
    final c = json.decode(readTextFile(versionsCache));
    // Make the cache artificially old.
    c['timestamp'] =
        DateTime.now().subtract(Duration(days: 5)).toIso8601String();
    writeTextFile(versionsCache, json.encode(c));
    globalPackageServer
        .add((builder) => builder.discontinue('foo', replacementText: 'bar'));
    await pubGet(
        warning:
            'Package:foo has been discontinued it has been replaced by package:bar.');
    final c2 = json.decode(readTextFile(versionsCache));
    // Make a bad cached value to test that responses are actually from cache.
    c2['response']['isDiscontinued'] = false;
    writeTextFile(versionsCache, json.encode(c2));
    await pubGet(warning: isEmpty);
  });
}
// /private/var/folders/zf/dv4m6qs906n6t1zhjt9jfdw4006vgn/T/dart_test_dskJEn/cache/hosted/localhost%5856564/foo-versions.json.
