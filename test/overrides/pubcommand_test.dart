// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm || browser')
library;

import 'dart:async';
import 'dart:convert' show utf8;

import 'package:args/command_runner.dart';
import 'package:file/file.dart' as f;
import 'package:file/memory.dart';
import 'package:http/http.dart' as http;
import 'package:pub/pub.dart';
import 'package:test/test.dart';

import 'bytesink.dart';

void main() {
  test('ensurePubspecResolved in memory', () async {
    final fs = MemoryFileSystem();

    fs.directory('/workspace').createSync();
    fs.currentDirectory = '/workspace';
    fs.directory('/sdk/bin').createSync(recursive: true);

    final bs = ByteSink();

    final dart = Runner(
      fileSystem: fs,
      stdout: bs,
      stderr: bs,
      stdin: const Stream.empty(),
      platformVersion: '3.11.0',
      environment: {'PUB_CACHE': '/tmp/pub_cache', 'DART_ROOT': '/sdk'},
      httpClient: http.Client(),
    );

    final pubspec = fs.file('/workspace/pubspec.yaml');
    await pubspec.writeAsString('''
name: my_app
version: 1.0.0
environment:
  sdk: ^3.0.0
dependencies:
  retry:
''');

    final exitCode = await dart.run(['pub', 'get']);
    expect(exitCode, 0);

    expect(
      fs.file('/workspace/.dart_tool/package_config.json').existsSync(),
      isTrue,
    );

    expect(utf8.decode(bs.bytes), contains('Changed 1 dependency'));
  });
}

class Runner extends CommandRunner<int> {
  final f.FileSystem fileSystem;
  final Map<String, String> environment;
  final String platformVersion;
  final Stream<List<int>> stdin;
  final StreamSink<List<int>> stdout;
  final StreamSink<List<int>> stderr;
  final http.Client httpClient;

  Runner({
    required this.fileSystem,
    required this.environment,
    required this.platformVersion,
    required this.stdin,
    required this.stdout,
    required this.stderr,
    required this.httpClient,
  }) : super('dart', 'dart pub emulator') {
    addCommand(
      pubCommand(
        isVerbose: () => false,
        fileSystem: fileSystem,
        environment: environment,
        platformVersion: platformVersion,
        stdin: stdin,
        stdout: stdout,
        stderr: stderr,
        httpClient: httpClient,
      ),
    );
  }
}
