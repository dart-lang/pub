// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';
import '../golden_file.dart';

const _command_runner = 'tool/test-bin/pub_command_runner.dart';

String snapshot;

/// Runs `dart tool/test-bin/pub_command_runner.dart [args]` and appends the output to [buffer].
Future<void> runEmbedding(List<String> args, StringBuffer buffer,
    {Map<String, String> environment, dynamic exitCode = 0}) async {
  final process = await TestProcess.start(
      Platform.resolvedExecutable, [snapshot, ...args],
      environment: environment);
  await process.shouldExit(exitCode);

  buffer.writeln([
    '\$ $_command_runner ${args.join(' ')}',
    ...await process.stdout.rest.toList(),
  ].join('\n'));
  final stdErr = await process.stderr.rest.toList();
  if (stdErr.isNotEmpty) {
    buffer.writeln(stdErr.map((e) => '[E] $e').join('\n'));
  }
  buffer.write('\n');
}

Future<void> main() async {
  setUpAll(() async {
    final tempDir = Directory.systemTemp.createTempSync();
    snapshot = path.join(tempDir.path, 'command_runner.dart.snapshot');
    final r = Process.runSync(
        Platform.resolvedExecutable, ['--snapshot=$snapshot', _command_runner]);
    expect(r.exitCode, 0, reason: r.stderr);
  });

  tearDownAll(() {
    File(snapshot).parent.deleteSync(recursive: true);
  });
  test('help text', () async {
    final buffer = StringBuffer();
    await runEmbedding([''], buffer, exitCode: 64);
    await runEmbedding(['--help'], buffer);
    await runEmbedding(['pub'], buffer, exitCode: 64);
    await runEmbedding(['pub', '--help'], buffer);
    await runEmbedding(['pub', 'get', '--help'], buffer);
    await runEmbedding(['pub', 'global'], buffer, exitCode: 64);
    expectMatchesGoldenFile(
        buffer.toString(), 'test/embedding/goldens/helptext.txt');
  });
}
