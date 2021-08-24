#!/usr/bin/env dart
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart=2.10

/// Test wrapper script.
/// Many of the integration tests runs the `pub` command, this is slow if every
/// invocation requires the dart compiler to load all the sources. This script
/// will create a `pub.XXX.dart.snapshot.dart2` which the tests can utilize.
/// After creating the snapshot this script will forward arguments to
/// `pub run test`, and ensure that the snapshot is deleted after tests have been
/// run.
import 'dart:io';
import 'package:path/path.dart' as path;

import 'package:pub/src/dart.dart';
import 'package:pub/src/exceptions.dart';

Future<void> main(List<String> args) async {
  final pubSnapshotFilename = path.absolute(path.join(
      '.dart_tool', '_pub', 'pub.dart.snapshot.dart2'));
  final pubSnapshotIncrementalFilename = '$pubSnapshotFilename.incremental';
  try {
    print('Building snapshot');
    await precompile(
      executablePath: path.join('bin', 'pub.dart'),
      outputPath: pubSnapshotFilename,
      incrementalDillOutputPath: pubSnapshotIncrementalFilename,
      name: 'bin/pub.dart',
      packageConfigPath: path.join('.dart_tool', 'package_config.json'));
    final extension = Platform.isWindows ? '.bat' : '';
    final testProcess = await Process.start(
        path.join(path.dirname(Platform.resolvedExecutable), 'pub$extension'),
        ['run', 'test', ...args],
        environment: {'_PUB_TEST_SNAPSHOT': pubSnapshotFilename});
    await Future.wait([
      testProcess.stdout.pipe(stdout),
      testProcess.stderr.pipe(stderr),
    ]);
    exitCode = await testProcess.exitCode;
  } on ApplicationException catch (_) {
    exitCode = 1;
  } finally {
    try {
      await File(pubSnapshotFilename).delete();
    } on Exception {
      // snapshot didn't exist.
    }
  }
}
