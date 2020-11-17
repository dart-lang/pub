// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:pub/src/io.dart';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('checks out a package from Git', () async {
    ensureGit();

    await d.git(
        'foo.git', [d.libDir('foo'), d.libPubspec('foo', '1.0.0')]).create();

    await d.appDir({
      'foo': {'git': '../foo.git'}
    }).create();

    await pubGet();

    await d.dir(cachePath, [
      d.dir('git', [
        d.dir('cache', [d.gitPackageRepoCacheDir('foo')]),
        d.gitPackageRevisionCacheDir('foo')
      ])
    ]).validate();

    expect(packageSpec('foo'), isNotNull);
  }, skip: true);

  test(
      'checks out a package from Git with a name that is not a valid '
      'file name in the url', () async {
    ensureGit();

    final descriptor =
        d.git('foo.git', [d.libDir('foo'), d.libPubspec('foo', '1.0.0')]);

    await descriptor.create();
    await runProcess('git', ['update-server-info'],
        workingDir: descriptor.io.path);
    const funkyName = '@:+*foo';

    final server =
        await _serveDirectory(p.join(descriptor.io.path, '.git'), funkyName);

    await d.appDir({
      'foo': {'git': 'http://localhost:${server.url.port}/$funkyName'}
    }).create();

    await pubGet();

    await d.dir(cachePath, [
      d.dir('git', [
        d.dir('cache', [d.gitPackageRepoCacheDir('____foo')]),
        d.gitPackageRevisionCacheDir('foo', repoName: '____foo')
      ])
    ]).validate();

    expect(packageSpec('foo'), isNotNull);
  });
}

Future<shelf.Server> _serveDirectory(String dir, String prefix) async {
  final server = await shelf_io.IOServer.bind('localhost', 0);
  server.mount((request) async {
    final path = request.url.path.substring(prefix.length + 1);
    try {
      return shelf.Response.ok(await File(p.join(dir, path)).readAsBytes());
    } catch (_) {
      return shelf.Response.notFound('File "$path" not found.');
    }
  });
  return server;
}
