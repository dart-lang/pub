// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';
import '../descriptor.dart' as d;
import '../golden_file.dart';
import '../test_pub.dart';

const _commandRunner = 'tool/test-bin/pub_command_runner.dart';

late String snapshot;

/// Runs `dart tool/test-bin/pub_command_runner.dart [args]` and appends the output to [buffer].
Future<void> runEmbeddingToBuffer(
  List<String> args,
  StringBuffer buffer, {
  String? workingDirectory,
  Map<String, String>? environment,
  dynamic exitCode = 0,
}) async {
  final process = await TestProcess.start(
    Platform.resolvedExecutable,
    ['--enable-asserts', snapshot, ...args],
    environment: {
      ...getPubTestEnvironment(),
      ...?environment,
    },
    workingDirectory: workingDirectory,
  );
  await process.shouldExit(exitCode);

  buffer.writeln([
    '\$ $_commandRunner ${args.join(' ')}',
    ...await process.stdout.rest.toList(),
  ].join('\n'));
  final stdErr = await process.stderr.rest.toList();
  if (stdErr.isNotEmpty) {
    buffer.writeln(stdErr.map((e) => '[E] $e').join('\n'));
  }
  buffer.write('\n');
}

extension on GoldenTestContext {
  /// Runs `dart tool/test-bin/pub_command_runner.dart [args]` and compare to
  /// next section in golden file.
  Future<void> runEmbedding(
    List<String> args, {
    String? workingDirextory,
    Map<String, String>? environment,
    dynamic exitCode = 0,
  }) async {
    final buffer = StringBuffer();
    await runEmbeddingToBuffer(
      args,
      buffer,
      workingDirectory: workingDirextory,
      environment: environment,
      exitCode: exitCode,
    );

    expectNextSection(buffer.toString());
  }
}

Future<void> main() async {
  setUpAll(() async {
    final tempDir = Directory.systemTemp.createTempSync();
    snapshot = path.join(tempDir.path, 'command_runner.dart.snapshot');
    final r = Process.runSync(
        Platform.resolvedExecutable, ['--snapshot=$snapshot', _commandRunner]);
    expect(r.exitCode, 0, reason: r.stderr);
  });

  tearDownAll(() {
    File(snapshot).parent.deleteSync(recursive: true);
  });

  testWithGolden('run works, though hidden', (ctx) async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {
          'sdk': '0.1.2+3',
        },
      }),
      d.dir('bin', [
        d.file('main.dart', '''
import 'dart:io';
main() { 
  print('Hi');
  exit(123);
}
''')
      ]),
    ]).create();
    await ctx.runEmbedding(
      ['pub', 'get'],
      workingDirextory: d.path(appPath),
    );
    await ctx.runEmbedding(
      ['pub', 'run', 'bin/main.dart'],
      exitCode: 123,
      workingDirextory: d.path(appPath),
    );
  });

  test('analytics', () async {
    await servePackages()
      ..serve('foo', '1.0.0', deps: {'bar': 'any'})
      ..serve('bar', '1.0.0');
    await d.dir('dep', [
      d.pubspec({
        'name': 'dep',
        'environment': {'sdk': '>=0.0.0 <3.0.0'}
      })
    ]).create();
    final app = d.dir(appPath, [
      d.appPubspec({
        'foo': '1.0.0',
        // The path dependency should not go to analytics.
        'dep': {'path': '../dep'}
      })
    ]);
    await app.create();

    final buffer = StringBuffer();

    await runEmbeddingToBuffer(
      ['pub', 'get'],
      buffer,
      workingDirectory: app.io.path,
      environment: {...getPubTestEnvironment(), '_PUB_LOG_ANALYTICS': 'true'},
    );
    final analytics = buffer
        .toString()
        .split('\n')
        .where((line) => line.startsWith('[E] [analytics]: '))
        .map((line) => json.decode(line.substring('[E] [analytics]: '.length)));
    expect(analytics, {
      {
        'hitType': 'event',
        'message': {
          'category': 'pub-get',
          'action': 'foo',
          'label': '1.0.0',
          'value': 1,
          'cd1': 'direct',
          'ni': '1',
        }
      },
      {
        'hitType': 'event',
        'message': {
          'category': 'pub-get',
          'action': 'bar',
          'label': '1.0.0',
          'value': 1,
          'cd1': 'transitive',
          'ni': '1',
        }
      },
      {
        'hitType': 'timing',
        'message': {
          'variableName': 'resolution',
          'time': isA<int>(),
          'category': 'pub-get',
          'label': null
        }
      },
    });
  });
}
