// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import 'descriptor.dart';
import 'test_pub.dart';

Future<void> main() async {
  test('archive_sha256 is stored in lockfile and cache upon download',
      () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');
    server.serveContentHashes = true;
    await appDir(dependencies: {'foo': 'any'}).create();
    await pubGet();
    final lockfile = loadYaml(
      File(p.join(sandbox, appPath, 'pubspec.lock')).readAsStringSync(),
    );
    final sha256 = lockfile['packages']['foo']['description']['sha256'];
    expect(sha256, hasLength(64));
    await hostedHashesCache([
      file('foo-1.0.0.sha256', sha256),
    ]).validate();
  });

  test(
      'archive_sha256 is stored in lockfile upon download on legacy server without content hashes',
      () async {
    final server = await servePackages();
    server.serveContentHashes = false;
    server.serve('foo', '1.0.0');
    await appDir(dependencies: {'foo': 'any'}).create();
    await pubGet();
    final lockfile = loadYaml(
      File(p.join(sandbox, appPath, 'pubspec.lock')).readAsStringSync(),
    );
    final sha256 = lockfile['packages']['foo']['description']['sha256'];
    expect(sha256, hasLength(64));
    await hostedHashesCache([
      file('foo-1.0.0.sha256', sha256),
    ]).validate();
  });

  test('archive_sha256 is checked on download', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');
    server.overrideArchiveSha256(
      'foo',
      '1.0.0',
      'e7a7a0f6d9873e4c40cf68cc3cc9ca5b6c8cef6a2220241bdada4b9cb0083279',
    );
    await appDir(dependencies: {'foo': 'any'}).create();
    await pubGet(
      exitCode: exit_codes.TEMP_FAIL,
      silent: contains('Attempt #2'),
      error:
          contains('Downloaded archive for foo-1.0.0 had wrong content-hash.'),
      environment: {
        'PUB_MAX_HTTP_RETRIES': '2',
      },
    );
  });

  test('If content is updated on server we warn and update the lockfile',
      () async {
    final server = await servePackages();
    server.serveContentHashes = true;
    server.serve('foo', '1.0.0');
    await appDir(dependencies: {'foo': 'any'}).create();
    await pubGet();
    server.serve(
      'foo',
      '1.0.0',
      contents: [file('new_file.txt', 'This file could be malicious.')],
    );
    // Pub get will not revisit the file-listing if everything resolves, and only compare with a cached value.
    await pubGet();
    // Deleting the version-listing cache will cause it to be refetched, and the
    // warning will happen.
    File(p.join(globalServer.cachingPath, '.cache', 'foo-versions.json'))
        .deleteSync();
    await pubGet(
      warning: allOf(
        contains('Cached version of foo-1.0.0 has wrong hash - redownloading.'),
        contains(
          'The existing content-hash from pubspec.lock doesn\'t match contents for:',
        ),
        contains('* foo-1.0.0 from "${server.url}"\n'),
      ),
      exitCode: exit_codes.SUCCESS,
    );
    final lockfile = loadYaml(
      File(p.join(sandbox, appPath, 'pubspec.lock')).readAsStringSync(),
    );
    final newHash = lockfile['packages']['foo']['description']['sha256'];
    expect(newHash, await server.peekArchiveSha256('foo', '1.0.0'));
  });

  test(
      'If content is updated on legacy server, and the download needs refreshing we warn and update the lockfile',
      () async {
    final server = await servePackages();
    server.serveContentHashes = false;
    server.serve('foo', '1.0.0');
    await appDir(dependencies: {'foo': 'any'}).create();
    await pubGet();
    server.serve(
      'foo',
      '1.0.0',
      contents: [file('new_file.txt', 'This file could be malicious.')],
    );
    // Deleting the hash-file cache will cause it to be refetched, and the
    // warning will happen.
    File(p.join(globalServer.hashesCachingPath, 'foo-1.0.0.sha256'))
        .deleteSync();

    await pubGet(
      warning: allOf([
        contains(
          'The existing content-hash from pubspec.lock doesn\'t match contents for:',
        ),
        contains('* foo-1.0.0 from "${globalServer.url}"'),
      ]),
      exitCode: exit_codes.SUCCESS,
    );
    final lockfile = loadYaml(
      File(p.join(sandbox, appPath, 'pubspec.lock')).readAsStringSync(),
    );
    final newHash = lockfile['packages']['foo']['description']['sha256'];
    expect(newHash, await server.peekArchiveSha256('foo', '1.0.0'));
  });

  test(
      'sha256 in cache is checked on pub get - warning and redownload on legacy server without content-hashes',
      () async {
    final server = await servePackages();
    server.serveContentHashes = false;
    server.serve('foo', '1.0.0');
    await appDir(dependencies: {'foo': 'any'}).create();
    await pubGet();
    final lockfile = loadYaml(
      File(p.join(sandbox, appPath, 'pubspec.lock')).readAsStringSync(),
    );
    final originalHash = lockfile['packages']['foo']['description']['sha256'];
    // Create wrong hash on disk.
    await hostedHashesCache([
      file(
        'foo-1.0.0.sha256',
        'e7a7a0f6d9873e4c40cf68cc3cc9ca5b6c8cef6a2220241bdada4b9cb0083279',
      ),
    ]).create();

    await pubGet(
      warning: 'Cached version of foo-1.0.0 has wrong hash - redownloading.',
    );
    await hostedHashesCache([
      file('foo-1.0.0.sha256', originalHash),
    ]).validate();
  });

  test('sha256 in cache is checked on pub get - warning and redownload',
      () async {
    final server = await servePackages();
    server.serveContentHashes = true;
    server.serve('foo', '1.0.0');
    await appDir(dependencies: {'foo': 'any'}).create();
    await pubGet();
    final lockfile = loadYaml(
      File(p.join(sandbox, appPath, 'pubspec.lock')).readAsStringSync(),
    );
    final originalHash = lockfile['packages']['foo']['description']['sha256'];
    await hostedHashesCache([
      file(
        'foo-1.0.0.sha256',
        'e7a7a0f6d9873e4c40cf68cc3cc9ca5b6c8cef6a2220241bdada4b9cb0083279',
      ),
    ]).create();

    await pubGet(
      warning: 'Cached version of foo-1.0.0 has wrong hash - redownloading.',
    );
    await hostedHashesCache([
      file('foo-1.0.0.sha256', originalHash),
    ]).validate();
  });

  test(
      'Legacy lockfile without content-hashes is updated with the hash on pub get on legacy server without content-hashes',
      () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');
    server.serveContentHashes = false;
    await appDir(dependencies: {'foo': 'any'}).create();
    await pubGet();
    // Pretend we had no hash in the lockfile.
    final lockfile = YamlEditor(
      File(p.join(sandbox, appPath, 'pubspec.lock')).readAsStringSync(),
    );
    final originalContentHash = lockfile
        .remove(['packages', 'foo', 'description', 'sha256']).value as String;
    File(p.join(sandbox, appPath, 'pubspec.lock')).writeAsStringSync(
      lockfile.toString(),
    );
    await pubGet();
    final lockfile2 = YamlEditor(
      File(p.join(sandbox, appPath, 'pubspec.lock')).readAsStringSync(),
    );
    expect(
      lockfile2.parseAt(['packages', 'foo', 'description', 'sha256']).value,
      originalContentHash,
    );
  });

  test(
      'Legacy lockfile without content-hashes is updated with the hash on pub get',
      () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');
    server.serveContentHashes = true;
    await appDir(dependencies: {'foo': 'any'}).create();
    await pubGet();
    // Pretend we had no hash in the lockfile.
    final lockfile = YamlEditor(
      File(p.join(sandbox, appPath, 'pubspec.lock')).readAsStringSync(),
    );
    final originalContentHash = lockfile
        .remove(['packages', 'foo', 'description', 'sha256']).value as String;
    File(p.join(sandbox, appPath, 'pubspec.lock')).writeAsStringSync(
      lockfile.toString(),
    );
    await pubGet();
    final lockfile2 = YamlEditor(
      File(p.join(sandbox, appPath, 'pubspec.lock')).readAsStringSync(),
    );
    expect(
      lockfile2.parseAt(['packages', 'foo', 'description', 'sha256']).value,
      originalContentHash,
    );
  });

  test('Badly formatted hash - warning and redownload', () async {
    final server = await servePackages();
    server.serveContentHashes = true;
    server.serve('foo', '1.0.0');
    await appDir(dependencies: {'foo': 'any'}).create();
    await pubGet();
    final lockfile = loadYaml(
      File(p.join(sandbox, appPath, 'pubspec.lock')).readAsStringSync(),
    );
    final originalHash = lockfile['packages']['foo']['description']['sha256'];
    await hostedHashesCache([
      file(
        'foo-1.0.0.sha256',
        'e',
      ),
    ]).create();

    await pubGet(
      warning: 'Cached version of foo-1.0.0 has wrong hash - redownloading.',
    );
    await hostedHashesCache([
      file('foo-1.0.0.sha256', originalHash),
    ]).validate();
  });
}
