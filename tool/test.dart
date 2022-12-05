#!/usr/bin/env dart
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Test wrapper script. Many of the integration tests runs the `pub` command,
/// this is slow if every invocation requires the dart compiler to load all the
/// sources. This script will create a `pub.dart.dill` snapshot which the tests
/// can utilize. After creating the snapshot this script will forward arguments
/// to the test runner, and ensure that the snapshot is deleted after tests have
/// been run.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:test/src/executable.dart' as test;

/// A connection to a resident compiler.
///
/// Either established through the port at [residentInfoFilename] or a new
/// resident compiler is opened.
///
/// The compiler will itself time out after some time of inactivity.
class _CompilerConnection {
  static const residentInfoFilename = '.dart_tool/pub/.resident_compiler';

  final StreamIterator<List<int>> output;
  final Sink<List<int>> input;
  final Socket socket;
  _CompilerConnection(this.input, this.output, this.socket);

  Future<void> compile(
      {required String entrypoint, required String incrementalDill}) async {
    input.add(utf8.encode(jsonEncode({
      'command': 'compile',
      'executable': entrypoint,
      'output-dill': incrementalDill,
    })));
    await output.moveNext();
    final result = json.decode(utf8.decode(output.current));
    if (!result['success']) {
      stderr.writeln('Failed building snapshot: ');
      stderr.writeln(result['compilerOutputLines'].join('\n'));
      exit(-1);
    }
    if (result['incremental'] ?? false) {
      stderr.writeln('incremental compilation');
    }
    if (result['returnedStoredKernel'] ?? false) {
      stderr.writeln('No update to pub compilation');
    }
  }

  void close() => socket.destroy();

  static Future<void> _startResidentCompiler() async {
    try {
      File(residentInfoFilename).deleteSync(recursive: true);
    } on IOException {
      // Probably the file didn't exist.
    }
    stderr.writeln('Restarting compiler');
    final process = await Process.start(
        Platform.resolvedExecutable,
        [
          path.join(
            path.dirname(Platform.resolvedExecutable),
            'snapshots/frontend_server.dart.snapshot',
          ),
          '--resident-info-file-name=$residentInfoFilename',
        ],
        mode: ProcessStartMode.detachedWithStdio);
    // Wait for the first line of output, indicating we can now find the address
    // of the compiler at [residentInfoFilename]
    await process.stdout.first;
  }

  static Future<_CompilerConnection?> _findResidentCompiler() async {
    String address;
    try {
      address = File(residentInfoFilename).readAsStringSync();
      stderr.writeln('Connecting to existing compiler...');
    } on IOException {
      return null;
    }

    final parts = address.split(' ').map((x) => x.split(':')).toList();
    final Socket socket;
    try {
      socket = await Socket.connect(parts[0][1], int.parse(parts[1][1]));
    } on IOException {
      stderr.writeln('Failed connecting to compiler at $address');
      return null;
    }
    return _CompilerConnection(socket, StreamIterator(socket), socket);
  }

  static Future<_CompilerConnection> getResidentCompiler() async {
    var connection = await _findResidentCompiler();
    if (connection == null) {
      await _startResidentCompiler();
      connection = await _findResidentCompiler();
      if (connection == null) {
        throw Exception('Could not start resident compiler');
      }
    }

    return connection;
  }
}

Future<void> compileSnapshot() async {
  final pubSnapshotFilename =
      path.absolute(path.join('.dart_tool', '_pub', 'pub.dart.dill'));
  final pubSnapshotIncrementalFilename = '$pubSnapshotFilename.incremental';

  final s = Stopwatch()..start();

  stderr.writeln('Building snapshot...');
  final compilerConnection = await _CompilerConnection.getResidentCompiler();
  await compilerConnection.compile(
      entrypoint: path.absolute('bin/pub.dart'),
      incrementalDill: pubSnapshotIncrementalFilename);
  compilerConnection.close();
  Directory(path.dirname(pubSnapshotFilename)).createSync(recursive: true);
  File(pubSnapshotIncrementalFilename).copySync(pubSnapshotFilename);
  stderr.writeln('Building snapshot took: ${s.elapsed.inMilliseconds} ms');
}

Future<void> main(List<String> args) async {
  if (args.isNotEmpty && args.first == 'precompiling') {
    // TODO(https://github.com/dart-lang/sdk/issues/50615): this should not be
    // needed I think.
    exit(0);
  }
  if (Platform.environment['FLUTTER_ROOT'] != null) {
    stderr.writeln(
      'WARNING: The tests will not run correctly with dart from a flutter checkout!',
    );
  }
  await compileSnapshot();
  test.main(args);
}
