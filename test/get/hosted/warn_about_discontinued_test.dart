// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart=2.10

import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:pub/src/io.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('Warns about discontinued dependencies', () async {
    await servePackages((builder) => builder
      ..serve('foo', '1.2.3', deps: {'transitive': 'any'})
      ..serve('transitive', '1.0.0'));
    await d.appDir({'foo': '1.2.3'}).create();
    await pubGet();

    globalPackageServer.add((builder) => builder
      ..discontinue('foo')
      ..discontinue('transitive'));
    // A pub get straight away will not trigger the warning, as we cache
    // responses for a while.
    await pubGet();
    final fooVersionsCache =
        p.join(globalPackageServer.cachingPath, '.cache', 'foo-versions.json');
    final transitiveVersionsCache = p.join(
        globalPackageServer.cachingPath, '.cache', 'transitive-versions.json');
    expect(fileExists(fooVersionsCache), isTrue);
    expect(fileExists(transitiveVersionsCache), isTrue);
    deleteEntry(fooVersionsCache);
    deleteEntry(transitiveVersionsCache);
    // We warn only about the direct dependency here:
    await pubGet(output: '''
Resolving dependencies...
  foo 1.2.3 (discontinued)
Got dependencies!
''');
    expect(fileExists(fooVersionsCache), isTrue);
    final c = json.decode(readTextFile(fooVersionsCache));
    // Make the cache artificially old.
    c['_fetchedAt'] =
        DateTime.now().subtract(Duration(days: 5)).toIso8601String();
    writeTextFile(fooVersionsCache, json.encode(c));
    globalPackageServer
        .add((builder) => builder.discontinue('foo', replacementText: 'bar'));
    await pubGet(output: '''
Resolving dependencies...
  foo 1.2.3 (discontinued replaced by bar)
Got dependencies!''');
    final c2 = json.decode(readTextFile(fooVersionsCache));
    // Make a bad cached value to test that responses are actually from cache.
    c2['isDiscontinued'] = false;
    writeTextFile(fooVersionsCache, json.encode(c2));
    await pubGet(output: '''
Resolving dependencies...
Got dependencies!''');
    // Repairing the cache should reset the package listing caches.
    await runPub(args: ['cache', 'repair']);
    await pubGet(output: '''
Resolving dependencies...
  foo 1.2.3 (discontinued replaced by bar)
Got dependencies!''');
    // Test that --offline won't try to access the server for retrieving the
    // status.
    await serveErrors();
    await pubGet(args: ['--offline'], output: '''
Resolving dependencies...
  foo 1.2.3 (discontinued replaced by bar)
Got dependencies!''');
    deleteEntry(fooVersionsCache);
    deleteEntry(transitiveVersionsCache);
    await pubGet(args: ['--offline'], output: '''
Resolving dependencies...
Got dependencies!
''');
  });

  test('Warns about discontinued dev dependencies', () async {
    await servePackages((builder) => builder
      ..serve('foo', '1.2.3', deps: {'transitive': 'any'})
      ..serve('transitive', '1.0.0'));

    await d.dir(appPath, [
      d.file('pubspec.yaml', '''
name: myapp
dependencies:

dev_dependencies:
  foo: 1.2.3
environment:
  sdk: '>=0.1.2 <1.0.0'
''')
    ]).create();
    await pubGet();

    globalPackageServer.add((builder) => builder
      ..discontinue('foo')
      ..discontinue('transitive'));
    // A pub get straight away will not trigger the warning, as we cache
    // responses for a while.
    await pubGet();
    final fooVersionsCache =
        p.join(globalPackageServer.cachingPath, '.cache', 'foo-versions.json');
    expect(fileExists(fooVersionsCache), isTrue);
    deleteEntry(fooVersionsCache);
    // We warn only about the direct dependency here:
    await pubGet(output: '''
Resolving dependencies...
  foo 1.2.3 (discontinued)
Got dependencies!
''');
    expect(fileExists(fooVersionsCache), isTrue);
    final c = json.decode(readTextFile(fooVersionsCache));
    // Make the cache artificially old.
    c['_fetchedAt'] =
        DateTime.now().subtract(Duration(days: 5)).toIso8601String();
    writeTextFile(fooVersionsCache, json.encode(c));
    globalPackageServer
        .add((builder) => builder.discontinue('foo', replacementText: 'bar'));
    await pubGet(output: '''
Resolving dependencies...
  foo 1.2.3 (discontinued replaced by bar)
Got dependencies!''');
    final c2 = json.decode(readTextFile(fooVersionsCache));
    // Make a bad cached value to test that responses are actually from cache.
    c2['isDiscontinued'] = false;
    writeTextFile(fooVersionsCache, json.encode(c2));
    await pubGet(output: '''
Resolving dependencies...
Got dependencies!''');
    // Repairing the cache should reset the package listing caches.
    await runPub(args: ['cache', 'repair']);
    await pubGet(output: '''
Resolving dependencies...
  foo 1.2.3 (discontinued replaced by bar)
Got dependencies!''');
    // Test that --offline won't try to access the server for retrieving the
    // status.
    await serveErrors();
    await pubGet(args: ['--offline'], output: '''
Resolving dependencies...
  foo 1.2.3 (discontinued replaced by bar)
Got dependencies!''');
    deleteEntry(fooVersionsCache);
    await pubGet(args: ['--offline'], output: '''
Resolving dependencies...
Got dependencies!
''');
  });

  test('get does not fail when status listing fails', () async {
    await servePackages((builder) => builder..serve('foo', '1.2.3'));
    await d.appDir({'foo': '1.2.3'}).create();
    await pubGet();
    final fooVersionsCache =
        p.join(globalPackageServer.cachingPath, '.cache', 'foo-versions.json');
    expect(fileExists(fooVersionsCache), isTrue);
    deleteEntry(fooVersionsCache);
    // Serve 400 on all requests.
    globalPackageServer.extraHandlers
      ..clear()
      ..[RegExp('.*')] = (request) async => Response(400);

    /// Even if we fail to get status we still report success if versions don't unlock.
    await pubGet();
  });
}
