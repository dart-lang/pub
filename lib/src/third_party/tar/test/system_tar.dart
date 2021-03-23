// Wrapper around the `tar` command, for testing.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:tar/tar.dart' as tar;
import 'package:test/test.dart';

Future<Process> startTar(List<String> args, {String? baseDir}) {
  return Process.start('tar', args, workingDirectory: baseDir).then((proc) {
    expect(proc.exitCode, completion(0),
        reason: 'tar ${args.join(' ')} should complete normally');

    // Attach stderr listener, we don't expect any output on that
    late List<int> data;
    final sink = ByteConversionSink.withCallback((result) => data = result);
    proc.stderr.forEach(sink.add).then((Object? _) {
      sink.close();
      const LineSplitter().convert(utf8.decode(data)).forEach(stderr.writeln);
    });

    return proc;
  });
}

Stream<List<int>> createTarStream(Iterable<String> files,
    {String archiveFormat = 'gnu',
    String? sparseVersion,
    String? baseDir}) async* {
  final args = [
    '--format=$archiveFormat',
    '--create',
    ...files,
  ];

  if (sparseVersion != null) {
    args..add('--sparse')..add('--sparse-version=$sparseVersion');
  }

  final tar = await startTar(args, baseDir: baseDir);
  yield* tar.stdout;
}

Future<Process> writeToTar(
    List<String> args, Stream<tar.TarEntry> entries) async {
  final proc = await startTar(args);
  await entries.pipe(tar.tarWritingSink(proc.stdin));

  return proc;
}

extension ProcessUtils on Process {
  Stream<String> get lines {
    return this.stdout.transform(utf8.decoder).transform(const LineSplitter());
  }
}
