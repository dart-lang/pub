#!/usr/bin/env dart

import 'dart:convert';

/// Test wrapper script.
/// Many of the integration tests runs the `pub` command, this is slow if every
/// invocation requires the dart compiler to load all the sources. This script
/// will create a `pub.XXX.dart.snapshot.dart2` which the tests can utilize.
/// After creating the snapshot this script will forward arguments to
/// `pub run test`, and ensure that the snapshot is deleted after tests have been
/// run.
import 'dart:io';
import 'dart:math';
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
    if (args.isEmpty) {
      final tests = Directory('test')
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.path)
          .where((path) => path.endsWith('_test.dart'))
          .toList();
      final splits = <List<String>>[];
      final concurrency = max(1, Platform.numberOfProcessors - 2);
      print("Running $concurrency concurrent jobs");
      var l = tests.length ~/ concurrency;
      if (tests.length % concurrency != 0) l++;
      var t = 0;
      while (t < tests.length) {
        splits.add(tests.sublist(t, min(tests.length, t + l)));
        t += l;
      }
      exitCode = (await Future.wait(Iterable.generate(splits.length, (i) async {
        final split = splits[i];
        final extension = Platform.isWindows ? '.bat' : '';
        print("Testing $split");
        final testProcess = await Process.start(
            path.join(
                path.dirname(Platform.resolvedExecutable), 'pub$extension'),
            ['run', 'test', '-rexpanded', ...split],
            environment: {'_PUB_TEST_SNAPSHOT': pubSnapshotFilename});

        testProcess.stdout.listen((line) {
          stdout.add(utf8.encode('$i ${utf8.decode(line)}'));
        });
        testProcess.stderr.pipe(stderr);

        return await testProcess.exitCode;
      })))
          .fold(0, max);
    }
  } finally {
    try {
      await File(pubSnapshotFilename).delete();
    } on Exception {
      // snapshot didn't exist.
    }
  }
}
