// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm || browser')
library;

import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:io';
import 'dart:typed_data';

import 'package:file/memory.dart';
import 'package:pub/pub.dart';
import 'package:pub/src/io.dart' show withOverrides;
import 'package:test/test.dart';

void main() {
  test('ensurePubspecResolved in memory', () async {
    final fs = MemoryFileSystem();

    fs.directory('/workspace').createSync();
    fs.currentDirectory = '/workspace';
    fs.directory('/sdk/bin').createSync(recursive: true);

    final bs = _ByteSink();

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
dependencies:
  retry:
''');

        await ensurePubspecResolved(
          '/workspace',
          summaryOnly: false,
          onlyOutputWhenTerminal: false,
        );

        expect(
          fs.file('/workspace/.dart_tool/package_config.json').existsSync(),
          isTrue,
        );
      },
    );
    expect(utf8.decode(bs.bytes), contains('Changed 1 dependency'));
  });
}

final class _ByteSink implements StreamSink<List<int>> {
  final builder = BytesBuilder();
  final _completer = Completer<void>();

  /// Access the buffered bytes as a Uint8List
  Uint8List get bytes => builder.toBytes();

  @override
  void add(List<int> data) {
    builder.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    if (!_completer.isCompleted) {
      _completer.completeError(error, stackTrace);
    }
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await stream.forEach(add);
  }

  @override
  Future<void> close() async {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }

  @override
  Future<void> get done => _completer.future;
}
