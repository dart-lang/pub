// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pub/src/io.dart'
    show canonicalize, deleteEntry, dirExists, readTextFile, writeTextFile;
import 'package:pub/src/path.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

Future<PubProcess> _startPubWaitingForGlobalLock({
  required Iterable<String> args,
  FutureOr<void> Function()? whileWaiting,
}) async {
  final cacheRoot = canonicalize(pathInCache(''));
  Directory(cacheRoot).createSync(recursive: true);
  final lockFile = File(
    '$cacheRoot.global_packages.lock',
  ).openSync(mode: FileMode.append);
  var lockFileClosed = false;
  lockFile.lockSync();
  addTearDown(() {
    if (lockFileClosed) return;
    lockFile.unlockSync();
    lockFile.closeSync();
  });

  final process = await startPub(args: args);
  await expectLater(
    process.stdout,
    emitsThrough('Waiting to acquire the global package mutation lock...'),
  );
  if (whileWaiting != null) await whileWaiting();

  lockFile.unlockSync();
  lockFile.closeSync();
  lockFileClosed = true;
  return process;
}

void main() {
  test('holds the global package lock while activating', () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      pubspec: {
        'executables': {'foo': null},
      },
      contents: [
        d.dir('bin', [d.file('foo.dart', "main() => print('ok');")]),
      ],
    );

    final archiveSha256 = await server.peekArchiveSha256('foo', '1.0.0');
    final requestReceived = Completer<void>();
    final sendResponse = Completer<void>();
    addTearDown(() {
      if (!sendResponse.isCompleted) sendResponse.complete();
    });
    server.handle('/api/packages/foo', (request) async {
      requestReceived.complete();
      await sendResponse.future;
      return shelf.Response.ok(
        jsonEncode({
          'name': 'foo',
          'uploaders': ['nweiz@google.com'],
          'versions': [
            {
              'pubspec': {
                'name': 'foo',
                'version': '1.0.0',
                'environment': {'sdk': '^3.0.0'},
                'executables': {'foo': null},
              },
              'version': '1.0.0',
              'archive_url': '${server.url}/packages/foo/versions/1.0.0.tar.gz',
              'archive_sha256': archiveSha256,
            },
          ],
        }),
        headers: {HttpHeaders.contentTypeHeader: server.contentType},
      );
    });

    final configuredCacheRoot = p.normalize(pathInCache(''));
    Directory(configuredCacheRoot).createSync(recursive: true);
    var pubCache = configuredCacheRoot;
    if (!Platform.isWindows) {
      pubCache = p.join(d.sandbox, 'cache-link');
      Link(pubCache).createSync(configuredCacheRoot);
    }

    final pub = await startPub(
      args: ['global', 'activate', 'foo'],
      environment: {'PUB_CACHE': pubCache},
    );
    await requestReceived.future;

    final cacheRoot = canonicalize(configuredCacheRoot);
    final lockPath = '$cacheRoot.global_packages.lock';
    final lockedProbe = File(lockPath).openSync(mode: FileMode.append);
    try {
      expect(lockedProbe.lockSync, throwsA(isA<FileSystemException>()));
    } finally {
      lockedProbe.closeSync();
    }

    sendResponse.complete();
    await pub.shouldExit();

    final releasedProbe = File(lockPath).openSync(mode: FileMode.append);
    try {
      releasedProbe.lockSync();
      releasedProbe.unlockSync();
    } finally {
      releasedProbe.closeSync();
    }
  });

  test('git activation waits for the global package lock', () async {
    ensureGit();
    await d.git('foo.git', [
      d.libPubspec('foo', '1.0.0'),
      d.dir('bin', [d.file('foo.dart', "main() => print('ok');")]),
    ]).create();

    final pub = await _startPubWaitingForGlobalLock(
      args: ['global', 'activate', '-sgit', '../foo.git'],
    );
    await pub.shouldExit();
    await runPub(args: ['global', 'run', 'foo'], output: 'ok');
  });

  test('deactivation waits for the global package lock', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');
    await runPub(args: ['global', 'activate', 'foo']);

    final activePackageDir = p.join(pathInCache('global_packages'), 'foo');
    final pub = await _startPubWaitingForGlobalLock(
      args: ['global', 'deactivate', 'foo'],
      whileWaiting: () => expect(dirExists(activePackageDir), isTrue),
    );
    await pub.shouldExit();
    expect(dirExists(activePackageDir), isFalse);
  });

  test(
    'recompile and binstub refresh wait for the global package lock',
    () async {
      final server = await servePackages();
      server.serve(
        'foo',
        '1.0.0',
        pubspec: {
          'executables': {'script': null},
        },
        contents: [
          d.dir('bin', [d.file('script.dart', "main() => print('ok');")]),
        ],
      );
      await runPub(args: ['global', 'activate', 'foo']);

      await d.dir(cachePath, [
        d.dir('global_packages', [
          d.dir('foo', [
            d.dir('bin', [
              d.outOfDateSnapshot('script.dart-$versionSuffix.snapshot-1'),
            ]),
          ]),
        ]),
      ]).create();
      final snapshotPath = p.join(
        d.dir(cachePath).io.path,
        'global_packages',
        'foo',
        'bin',
        'script.dart-$versionSuffix.snapshot',
      );
      deleteEntry(snapshotPath);

      final binStubPath = p.join(
        d.dir(cachePath).io.path,
        'bin',
        binStubName('script'),
      );
      writeTextFile(binStubPath, '${readTextFile(binStubPath)}\nstale');

      final pub = await _startPubWaitingForGlobalLock(
        args: ['global', 'run', 'foo:script'],
        whileWaiting:
            () => expect(readTextFile(binStubPath), contains('stale')),
      );
      await pub.shouldExit();

      expect(File(snapshotPath).existsSync(), isTrue);
      expect(readTextFile(binStubPath), isNot(contains('stale')));
    },
  );

  test('cache repair waits for the global package lock', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');
    await runPub(args: ['global', 'activate', 'foo']);

    final activePackageDir = p.join(pathInCache('global_packages'), 'foo');
    final pub = await _startPubWaitingForGlobalLock(
      args: ['cache', 'repair', '--all'],
      whileWaiting: () => expect(dirExists(activePackageDir), isTrue),
    );
    await pub.shouldExit();
    expect(dirExists(activePackageDir), isTrue);
  });

  test('cache repair does not reacquire the lock for path packages', () async {
    await d.dir('foo', [
      d.pubspec({
        'name': 'foo',
        'executables': {'foo': null},
      }),
      d.dir('bin', [d.file('foo.dart', "main() => print('ok');")]),
    ]).create();

    await runPub(args: ['global', 'activate', '--source', 'path', '../foo']);
    await runPub(
      args: ['cache', 'repair', '--all'],
      output: contains('Reactivated 1 package.'),
    );

    await d.dir(cachePath, [
      d.dir('bin', [
        d.file(binStubName('foo'), contains('global run foo:foo')),
      ]),
    ]).validate();
  });
}
