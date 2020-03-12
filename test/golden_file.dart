// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

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
      goldenFile = File(path.join(workspaceDirectory, goldenFilePath));
    }
    goldenFile
      ..createSync(recursive: true)
      ..writeAsStringSync(actual);
  }
}
