// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:file/memory.dart';
import 'package:pub/pub.dart';
import 'package:pub/src/io.dart' show withOverrides;
import 'package:test/test.dart';

import 'iooverrides.dart';

void main() {
  test('ensurePubspecResolved in memory', () async {
    final fs = MemoryFileSystem();

    fs.directory('/workspace').createSync();
    fs.currentDirectory = '/workspace';
    fs.directory('/sdk/bin').createSync(recursive: true);

    final bs = ByteSink();

    await withOverrides(
      fileSystem: fs,
      stdout: bs,
      stderr: bs,
      stdin: const Stream.empty(),
      platformVersion: '3.11.0',
      environment: {'PUB_CACHE': '/tmp/pub_cache', 'DART_ROOT': '/sdk'},
      () async {
        final pubspec = File('/workspace/pubspec.yaml');
        await pubspec.writeAsString('''
name: my_app
version: 1.0.0
environment:
  sdk: ^3.0.0
''');

        await ensurePubspecResolved('/workspace');

        expect(
          fs.file('/workspace/.dart_tool/package_config.json').existsSync(),
          isTrue,
        );
      },
    );
  });
}
