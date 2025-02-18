#!/usr/bin/env -S dart run -r
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Test wrapper script.
/// Many of the integration tests runs the `pub` command, this is slow if every
/// invocation requires the dart compiler to load all the sources. This script
/// will create a `pub.XXX.dart.snapshot.dart2` which the tests can utilize.
/// After creating the snapshot this script will forward arguments to
/// `pub run test`, and ensure that the snapshot is deleted after tests have
/// been run.
library;

import 'dart:io';
import 'package:path/path.dart' as p;

import 'package:pub/src/dart.dart';
import 'package:pub/src/exceptions.dart';

Future<void> main(List<String> args) async {
  if (Platform.environment['FLUTTER_ROOT'] != null) {
    stderr.writeln(
      'WARNING: '
      'The tests will not run correctly with dart from a flutter checkout!',
    );
  }
  Process? testProcess;
  final sub = ProcessSignal.sigint.watch().listen((signal) {
    testProcess?.kill(signal);
  });
  final pubSnapshotFilename = p.absolute(
    p.join('.dart_tool', '_pub', 'pub.dart.snapshot.dart2'),
  );
  try {
    final stopwatch = Stopwatch()..start();
    stderr.write('Building snapshot...');
    await precompile(
      executablePath: p.join('bin', 'pub.dart'),
      outputPath: pubSnapshotFilename,
      name: 'bin/pub.dart',
      packageConfigPath: p.join('.dart_tool', 'package_config.json'),
    );
    stderr.writeln(' (${stopwatch.elapsed.inMilliseconds}ms)');
    testProcess = await Process.start(
      Platform.resolvedExecutable,
      ['run', 'test', ...args],
      environment: {'_PUB_TEST_SNAPSHOT': pubSnapshotFilename},
      mode: ProcessStartMode.inheritStdio,
    );
    exitCode = await testProcess.exitCode;
  } on ApplicationException catch (e) {
    stderr.writeln('Failed building snapshot: $e');
    exitCode = 1;
  } finally {
    await sub.cancel();
  }
}
