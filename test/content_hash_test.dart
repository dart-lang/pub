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
    await appDir({'foo': 'any'}).create();
    await pubGet();
    final lockfile = loadYaml(
        File(p.join(sandbox, appPath, 'pubspec.lock')).readAsStringSync());
    final sha256 = lockfile['packages']['foo']['description']['sha256'];
    expect(sha256, hasLength(64));
    await hostedCache([
      dir('.hashes', [
        file('foo-1.0.0.sha256', sha256),
      ])
    ]).validate();
  });

  test(
      'archive_sha256 is stored in lockfile upon download on legacy server without content hashes',
      () async {
    final server = await servePackages();
    server.serveContentHashes = false;
    server.serve('foo', '1.0.0');
    await appDir({'foo': 'any'}).create();
    await pubGet();
    final lockfile = loadYaml(
        File(p.join(sandbox, appPath, 'pubspec.lock')).readAsStringSync());
    final sha256 = lockfile['packages']['foo']['description']['sha256'];
    expect(sha256, hasLength(64));
    await hostedCache([
      dir('.hashes', [
        file('foo-1.0.0.sha256', sha256),
      ])
    ]).validate();
  });

  test('archive_sha256 is checked on download', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');
    server.setSha256('foo', '1.0.0',
        'e7a7a0f6d9873e4c40cf68cc3cc9ca5b6c8cef6a2220241bdada4b9cb0083279');
    await appDir({'foo': 'any'}).create();
    await pubGet(
      error:
          contains('Downloaded archive for foo-1.0.0 had wrong content-hash.'),
      exitCode: exit_codes.DATA,
    );
  });

  test('If content is updated on server we refuse to continue', () async {
    final server = await servePackages();
    server.serveContentHashes = true;
    server.serve('foo', '1.0.0');
    await appDir({'foo': 'any'}).create();
    await pubGet();
    server.serve('foo', '1.0.0',
        contents: [file('new_file.txt', 'This file could be malicious.')]);
    // Pub get will not revisit the file-listing if everything resolves, and only compare with a cached value.
    await pubGet();
    // Deleting the version-listing cache will cause it to be refetched, and the error will happen.
    File(p.join(globalServer.cachingPath, '.cache', 'foo-versions.json'))
        .deleteSync();

    await pubGet(
      error: allOf(
        contains('Cached version of foo-1.0.0 has wrong hash - redownloading.'),
        contains(
            'Cache entry for foo-1.0.0 does not have content-hash matching lockfile.'),
      ),
      exitCode: exit_codes.DATA,
    );
  });

  test(
      'sha256 in cache is checked on pub get - warning and redownload on legacy server without content-hashes',
      () async {
    final server = await servePackages();
    server.serveContentHashes = false;
    server.serve('foo', '1.0.0');
    await appDir({'foo': 'any'}).create();
    await pubGet();
    final lockfile = loadYaml(
        File(p.join(sandbox, appPath, 'pubspec.lock')).readAsStringSync());
    final originalHash = lockfile['packages']['foo']['description']['sha256'];
    // Create wrong hash on disk.
    await hostedCache([
      dir('.hashes', [
        file('foo-1.0.0.sha256',
            'e7a7a0f6d9873e4c40cf68cc3cc9ca5b6c8cef6a2220241bdada4b9cb0083279'),
      ])
    ]).create();

    await pubGet(
        warning: 'Cached version of foo-1.0.0 has wrong hash - redownloading.');
    await hostedCache([
      dir('.hashes', [
        file('foo-1.0.0.sha256', originalHash),
      ])
    ]).validate();
  });

  test('sha256 in cache is checked on pub get - warning and redownload',
      () async {
    final server = await servePackages();
    server.serveContentHashes = true;
    server.serve('foo', '1.0.0');
    await appDir({'foo': 'any'}).create();
    await pubGet();
    final lockfile = loadYaml(
        File(p.join(sandbox, appPath, 'pubspec.lock')).readAsStringSync());
    final originalHash = lockfile['packages']['foo']['description']['sha256'];
    await hostedCache([
      dir('.hashes', [
        file('foo-1.0.0.sha256',
            'e7a7a0f6d9873e4c40cf68cc3cc9ca5b6c8cef6a2220241bdada4b9cb0083279'),
      ])
    ]).create();

    await pubGet(
        warning: 'Cached version of foo-1.0.0 has wrong hash - redownloading.');
    await hostedCache([
      dir('.hashes', [
        file('foo-1.0.0.sha256', originalHash),
      ])
    ]).validate();
  });
  test(
      'Legacy lockfile without content-hashes is updated with the hash on pub get on legacy server without content-hashes',
      () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');
    server.serveContentHashes = false;
    await appDir({'foo': 'any'}).create();
    await pubGet();
    // Pretend we had no hash in the lockfile.
    final lockfile = YamlEditor(
        File(p.join(sandbox, appPath, 'pubspec.lock')).readAsStringSync());
    final originalContentHash = lockfile
        .remove(['packages', 'foo', 'description', 'sha256']).value as String;
    File(p.join(sandbox, appPath, 'pubspec.lock')).writeAsStringSync(
      lockfile.toString(),
    );
    await pubGet();
    final lockfile2 = YamlEditor(
        File(p.join(sandbox, appPath, 'pubspec.lock')).readAsStringSync());
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
    await appDir({'foo': 'any'}).create();
    await pubGet();
    // Pretend we had no hash in the lockfile.
    final lockfile = YamlEditor(
        File(p.join(sandbox, appPath, 'pubspec.lock')).readAsStringSync());
    final originalContentHash = lockfile
        .remove(['packages', 'foo', 'description', 'sha256']).value as String;
    File(p.join(sandbox, appPath, 'pubspec.lock')).writeAsStringSync(
      lockfile.toString(),
    );
    await pubGet();
    final lockfile2 = YamlEditor(
        File(p.join(sandbox, appPath, 'pubspec.lock')).readAsStringSync());
    expect(
      lockfile2.parseAt(['packages', 'foo', 'description', 'sha256']).value,
      originalContentHash,
    );
  });
}
