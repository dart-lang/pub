#!/usr/bin/env dart

/// Test wrapper script.
/// Many of the integration tests runs the `pub` command, this is slow if every
/// invocation requires the dart compiler to load all the sources. This script
/// will create a `pub.XXX.dart.snapshot.dart2` which the tests can utilize.
/// After creating the snapshot this script will forward arguments to
/// `pub run test`, and ensure that the snapshot is deleted after tests have been
/// run.
import 'dart:io';
import 'package:path/path.dart' as path;

Future<void> main(List<String> args) async {
  final pubSnapshotFilename = path.join(
      (await Directory.systemTemp.createTemp()).path,
      'pub.dart.snapshot.dart2');
  try {
    print('Building snapshot');
    final stopwatch = Stopwatch()..start();
    final root = path.dirname(path.dirname(Platform.script.path));
    final compilationResult = await Process.run(Platform.resolvedExecutable, [
      '--snapshot=$pubSnapshotFilename',
      path.join(root, 'bin', 'pub.dart')
    ]);
    stopwatch.stop();
    if (compilationResult.exitCode != 0) {
      print(
          'Failed building snapshot: ${compilationResult.stdout} ${compilationResult.stderr}');
      exitCode = compilationResult.exitCode;
      return;
    }
    print('Took ${stopwatch.elapsedMilliseconds} milliseconds');
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
  } finally {
    try {
      await File(pubSnapshotFilename).delete();
    } on Exception {
      // snapshot didn't exist.
    }
  }
}
