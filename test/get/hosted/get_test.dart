// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:pub/src/exit_codes.dart';
import 'package:pub/src/io.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('gets a package from a pub server and validates its CRC32C checksum',
      () async {
    final server = await servePackages();
    server.serve('foo', '1.2.3');

    expect(await server.peekArchiveChecksumHeader('foo', '1.2.3'), isNotNull);

    await d.appDir(dependencies: {'foo': '1.2.3'}).create();

    await pubGet();

    await d.cacheDir({'foo': '1.2.3'}).validate();
    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '1.2.3'),
    ]).validate();
  });

  group('gets a package from a pub server without validating its checksum', () {
    late PackageServer server;

    setUp(() async {
      server = await servePackages()
        ..serveChecksums = false
        ..serve('foo', '1.2.3')
        ..serve(
          'bar',
          '1.2.3',
          headers: {
            'x-goog-hash': ['']
          },
        )
        ..serve(
          'baz',
          '1.2.3',
          headers: {
            'x-goog-hash': ['md5=loremipsum']
          },
        );
    });

    test('because of omitted checksum header', () async {
      expect(await server.peekArchiveChecksumHeader('foo', '1.2.3'), isNull);

      await d.appDir(dependencies: {'foo': '1.2.3'}).create();

      await pubGet();

      await d.cacheDir({'foo': '1.2.3'}).validate();
      await d.appPackageConfigFile([
        d.packageConfigEntry(name: 'foo', version: '1.2.3'),
      ]).validate();
    });

    test('because of empty checksum header', () async {
      expect(await server.peekArchiveChecksumHeader('bar', '1.2.3'), '');

      await d.appDir(dependencies: {'bar': '1.2.3'}).create();

      await pubGet();

      await d.cacheDir({'bar': '1.2.3'}).validate();
      await d.appPackageConfigFile([
        d.packageConfigEntry(name: 'bar', version: '1.2.3'),
      ]).validate();
    });

    test('because of missing CRC32C in checksum header', () async {
      expect(
        await server.peekArchiveChecksumHeader('baz', '1.2.3'),
        'md5=loremipsum',
      );

      await d.appDir(dependencies: {'baz': '1.2.3'}).create();

      await pubGet();

      await d.cacheDir({'baz': '1.2.3'}).validate();
      await d.appPackageConfigFile([
        d.packageConfigEntry(name: 'baz', version: '1.2.3'),
      ]).validate();
    });
  });

  test('URL encodes the package name', () async {
    await servePackages();

    await d.appDir(dependencies: {'bad name!': '1.2.3'}).create();

    await pubGet(
      error: allOf([
        contains(
            "Because myapp depends on bad name! any which doesn't exist (could "
            'not find package bad name! at http://localhost:'),
        contains('), version solving failed.')
      ]),
      exitCode: exit_codes.UNAVAILABLE,
    );
  });

  test('gets a package from a non-default pub server', () async {
    // Make the default server serve errors. Only the custom server should
    // be accessed.
    (await servePackages()).serveErrors();

    var server = await startPackageServer();
    server.serve('foo', '1.2.3');

    await d.appDir(
      dependencies: {
        'foo': {
          'version': '1.2.3',
          'hosted': {'name': 'foo', 'url': 'http://localhost:${server.port}'}
        }
      },
    ).create();

    await pubGet();

    await d.cacheDir({'foo': '1.2.3'}, port: server.port).validate();
    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '1.2.3', server: server),
    ]).validate();
  });

  test('recognizes and retries a package with a CRC32C checksum mismatch',
      () async {
    var server = await startPackageServer();

    server.serve(
      'foo',
      '1.2.3',
      headers: {
        'x-goog-hash': PackageServer.composeChecksumHeader(crc32c: 3381945770)
      },
    );

    await d.appDir(
      dependencies: {
        'foo': {
          'version': '1.2.3',
          'hosted': {'name': 'foo', 'url': 'http://localhost:${server.port}'}
        }
      },
    ).create();

    await pubGet(
      exitCode: exit_codes.TEMP_FAIL,
      error: RegExp(
          r'''Package archive for foo 1.2.3 downloaded from "(.+)" has '''
          r'''"x-goog-hash: crc32c=(\d+)", which doesn't match the checksum '''
          r'''of the archive downloaded\.'''),
      silent: contains('Attempt #2'),
      environment: {
        'PUB_MAX_HTTP_RETRIES': '2',
      },
    );
  });

  group('recognizes bad checksum header and retries', () {
    late PackageServer server;

    setUp(() async {
      server = await servePackages()
        ..serve(
          'foo',
          '1.2.3',
          headers: {
            'x-goog-hash': ['crc32c=,md5=']
          },
        )
        ..serve(
          'bar',
          '1.2.3',
          headers: {
            'x-goog-hash': ['crc32c=loremipsum,md5=loremipsum']
          },
        )
        ..serve(
          'baz',
          '1.2.3',
          headers: {
            'x-goog-hash': ['crc32c=MTIzNDU=,md5=NTQzMjE=']
          },
        );
    });

    test('when the CRC32C checksum is empty', () async {
      await d.appDir(
        dependencies: {
          'foo': {
            'version': '1.2.3',
            'hosted': {'name': 'foo', 'url': 'http://localhost:${server.port}'}
          }
        },
      ).create();

      await pubGet(
        exitCode: exit_codes.TEMP_FAIL,
        error: contains(
            'Package archive "foo-1.2.3.tar.gz" has a malformed CRC32C '
            'checksum in its response headers'),
        silent: contains('Attempt #2'),
        environment: {
          'PUB_MAX_HTTP_RETRIES': '2',
        },
      );
    });

    test('when the CRC32C checksum has bad encoding', () async {
      await d.appDir(
        dependencies: {
          'bar': {
            'version': '1.2.3',
            'hosted': {'name': 'bar', 'url': 'http://localhost:${server.port}'}
          }
        },
      ).create();

      await pubGet(
        exitCode: exit_codes.TEMP_FAIL,
        error: contains(
            'Package archive "bar-1.2.3.tar.gz" has a malformed CRC32C '
            'checksum in its response headers'),
        silent: contains('Attempt #2'),
        environment: {
          'PUB_MAX_HTTP_RETRIES': '2',
        },
      );
    });

    test('when the CRC32C checksum is malformed', () async {
      await d.appDir(
        dependencies: {
          'baz': {
            'version': '1.2.3',
            'hosted': {'name': 'baz', 'url': 'http://localhost:${server.port}'}
          }
        },
      ).create();

      await pubGet(
        exitCode: exit_codes.TEMP_FAIL,
        error: contains(
            'Package archive "baz-1.2.3.tar.gz" has a malformed CRC32C '
            'checksum in its response headers'),
        silent: contains('Attempt #2'),
        environment: {
          'PUB_MAX_HTTP_RETRIES': '2',
        },
      );
    });
  });

  test('gets a package from a pub server that uses gzip response compression',
      () async {
    final server = await servePackages();
    server.autoCompress = true;
    server.serveChecksums = false;
    server.serve('foo', '1.2.3');

    expect(await server.peekArchiveChecksumHeader('foo', '1.2.3'), isNull);

    await d.appDir(dependencies: {'foo': '1.2.3'}).create();

    await pubGet();

    await d.cacheDir({'foo': '1.2.3'}).validate();
    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '1.2.3'),
    ]).validate();
  });

  test(
      'gets a package from a pub server that uses gzip response compression '
      'and validates its CRC32C checksum', () async {
    final server = await servePackages();
    server.autoCompress = true;
    server.serve('foo', '1.2.3');

    expect(await server.peekArchiveChecksumHeader('foo', '1.2.3'), isNotNull);

    await d.appDir(dependencies: {'foo': '1.2.3'}).create();

    await pubGet();

    await d.cacheDir({'foo': '1.2.3'}).validate();
    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '1.2.3'),
    ]).validate();
  });

  group('categorizes dependency types in the lockfile', () {
    setUp(() async {
      await servePackages()
        ..serve('foo', '1.2.3', deps: {'bar': 'any'})
        ..serve('bar', '1.2.3')
        ..serve('baz', '1.2.3', deps: {'qux': 'any'})
        ..serve('qux', '1.2.3')
        ..serve('zip', '1.2.3', deps: {'zap': 'any'})
        ..serve('zap', '1.2.3');
    });

    test('for main, dev, and overridden dependencies', () async {
      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependencies': {'foo': 'any'},
          'dev_dependencies': {'baz': 'any'},
          'dependency_overrides': {'zip': 'any'}
        })
      ]).create();

      await pubGet();

      var packages = loadYaml(
        readTextFile(p.join(d.sandbox, appPath, 'pubspec.lock')),
      )['packages'];
      expect(
        packages,
        containsPair('foo', containsPair('dependency', 'direct main')),
      );
      expect(
        packages,
        containsPair('bar', containsPair('dependency', 'transitive')),
      );
      expect(
        packages,
        containsPair('baz', containsPair('dependency', 'direct dev')),
      );
      expect(
        packages,
        containsPair('qux', containsPair('dependency', 'transitive')),
      );
      expect(
        packages,
        containsPair('zip', containsPair('dependency', 'direct overridden')),
      );
      expect(
        packages,
        containsPair('zap', containsPair('dependency', 'transitive')),
      );
    });

    test('for overridden main and dev dependencies', () async {
      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependencies': {'foo': 'any'},
          'dev_dependencies': {'baz': 'any'},
          'dependency_overrides': {'foo': 'any', 'baz': 'any'}
        })
      ]).create();

      await pubGet();

      var packages = loadYaml(
        readTextFile(p.join(d.sandbox, appPath, 'pubspec.lock')),
      )['packages'];
      expect(
        packages,
        containsPair('foo', containsPair('dependency', 'direct main')),
      );
      expect(
        packages,
        containsPair('bar', containsPair('dependency', 'transitive')),
      );
      expect(
        packages,
        containsPair('baz', containsPair('dependency', 'direct dev')),
      );
      expect(
        packages,
        containsPair('qux', containsPair('dependency', 'transitive')),
      );
    });
  });

  test('Fails gracefully on tar.gz with duplicate entries', () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      contents: [
        d.dir('blah', [d.file('myduplicatefile'), d.file('myduplicatefile')])
      ],
    );
    await d.appDir(dependencies: {'foo': 'any'}).create();
    await pubGet(
      error:
          contains('Tar file contained duplicate path blah/myduplicatefile.'),
      exitCode: DATA,
    );
  });

  test('Fails gracefully when downloading archive', () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
    );
    final downloadPattern =
        RegExp(r'/packages/([^/]*)/versions/([^/]*).tar.gz');
    server.handle(
      downloadPattern,
      (request) => Response(403, body: 'Go away!'),
    );
    await d.appDir(dependencies: {'foo': 'any'}).create();
    await pubGet(
      error: contains('Package not available (authorization failed).'),
      exitCode: UNAVAILABLE,
    );
  });
}
