#!/usr/bin/env -S dart run -r

// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Test wrapper script.
/// Many of the integration tests runs the `pub` command, this is slow if every
/// invocation requires the dart compiler to load all the sources. This script
/// will build `pub` executable using `dart build cli` which the tests can
/// utilize.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
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
  final pubBuildDir = p.absolute(p.join('.dart_tool', '_pub_build'));
  final pubExecutable = p.join(
    pubBuildDir,
    'bundle',
    'bin',
    Platform.isWindows ? 'pub.exe' : 'pub',
  );
  try {
    final stopwatch = Stopwatch()..start();
    stderr.write('Building pub executable with `dart build cli`...');
    final buildResult = await Process.run(Platform.resolvedExecutable, [
      'build',
      'cli',
      '-t',
      p.join('bin', 'pub.dart'),
      '-o',
      pubBuildDir,
    ]);
    if (buildResult.exitCode != 0) {
      throw ApplicationException(
        'Failed to build pub executable:\n'
        '${buildResult.stderr}\n${buildResult.stdout}',
      );
    }
    stderr.writeln(' (${stopwatch.elapsed.inMilliseconds}ms)');
    testProcess = await Process.start(
      Platform.resolvedExecutable,
      ['run', 'test', ...args],
      environment: {
        '_PUB_TEST_EXECUTABLE': pubExecutable,
        '_PUB_TEST_SDK_DIR': p.dirname(p.dirname(Platform.resolvedExecutable)),
      },
      mode: ProcessStartMode.inheritStdio,
    );
    exitCode = await testProcess.exitCode;
  } on ApplicationException catch (e) {
    stderr.writeln('Failed building pub: $e');
    exitCode = 1;
  } finally {
    await sub.cancel();
  }
}
