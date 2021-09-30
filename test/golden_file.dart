// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart=2.10

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stack_trace/stack_trace.dart' show Trace;
import 'package:test/test.dart';

import 'test_pub.dart';

/// Will test [actual] against the contests of the file at [goldenFilePath].
///
/// If the file doesn't exist, the file is instead created containing [actual].
void expectMatchesGoldenFile(String actual, String goldenFilePath) {
  var goldenFile = File(goldenFilePath);
  if (goldenFile.existsSync()) {
    expect(
        actual, equals(goldenFile.readAsStringSync().replaceAll('\r\n', '\n')),
        reason: 'goldenFilePath: "$goldenFilePath"');
  } else {
    // This enables writing the updated file when run in otherwise hermetic
    // settings.
    //
    // This is to make updating the golden files easier in a bazel environment
    // See https://docs.bazel.build/versions/2.0.0/user-manual.html#run .
    final workspaceDirectory =
        Platform.environment['BUILD_WORKSPACE_DIRECTORY'];
    if (workspaceDirectory != null) {
      goldenFile = File(p.join(workspaceDirectory, goldenFilePath));
    }
    goldenFile
      ..createSync(recursive: true)
      ..writeAsStringSync(actual);
  }
}

/// Find the current `_test.dart` filename invoked from stack-trace.
String _findCurrentTestFilename() => Trace.current()
    .frames
    .lastWhere(
      (frame) =>
          frame.uri.isScheme('file') &&
          p.basename(frame.uri.toFilePath()).endsWith('_test.dart'),
    )
    .uri
    .toFilePath();

/// Run `pub <args>` and compare result to contents of golden file.
///
/// The a golden file with the recorded output will be created at:
///   `test/testdata/goldens/path/to/myfile_test/<filename>.txt`
/// , when `path/to/myfile_test.dart` is the `_test.dart` file from which this
/// function is called.
Future<void> runPubGoldenTest(
  String filename,
  List<String> args, {
  Map<String, String> environment,
  String workingDirectory,
}) async {
  final rel = p.relative(
    _findCurrentTestFilename().replaceAll(RegExp(r'\.dart$'), ''),
    from: p.join(p.current, 'test'),
  );
  final goldenFile = p.join(
    'test',
    'testdata',
    'goldens',
    rel,
    filename + '.txt',
  );

  final s = StringBuffer();
  await runPubIntoBuffer(
    args,
    s,
    environment: environment,
    workingDirectory: workingDirectory,
  );

  expectMatchesGoldenFile(s.toString(), goldenFile);
}
