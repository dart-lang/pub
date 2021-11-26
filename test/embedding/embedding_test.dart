// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

import '../descriptor.dart' as d;
import '../golden_file.dart';
import '../test_pub.dart';

const _commandRunner = 'tool/test-bin/pub_command_runner.dart';

late String snapshot;

final logFile = p.join(d.sandbox, cachePath, 'log', 'pub_log.txt');

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
    ...await process.stdout.rest.map(_filter).toList(),
  ].join('\n'));
  final stdErr = await process.stderr.rest.toList();
  if (stdErr.isNotEmpty) {
    buffer.writeln(stdErr.map(_filter).map((e) => '[E] $e').join('\n'));
  }
  buffer.write('\n');
}

extension on GoldenTestContext {
  /// Runs `dart tool/test-bin/pub_command_runner.dart [args]` and compare to
  /// next section in golden file.
  Future<void> runEmbedding(
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
    dynamic exitCode = 0,
  }) async {
    final buffer = StringBuffer();
    await runEmbeddingToBuffer(
      args,
      buffer,
      workingDirectory: workingDirectory,
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
    await servePackages();
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
      workingDirectory: d.path(appPath),
    );
    await ctx.runEmbedding(
      ['pub', 'run', 'bin/main.dart'],
      exitCode: 123,
      workingDirectory: d.path(appPath),
    );
  });

  testWithGolden(
      'logfile is written with --verbose and on unexpected exceptions',
      (context) async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');
    await d.appDir({'foo': 'any'}).create();

    await context.runEmbedding(
      ['pub', '--verbose', 'get'],
      workingDirectory: d.path(appPath),
    );
    context.expectNextSection(
      _filter(
        File(logFile).readAsStringSync(),
      ),
    );
    await context.runEmbedding(
      ['pub', 'fail'],
      workingDirectory: app.io.path,
      exitCode: 1,
    );
    context.expectNextSection(
      _filter(
        File(logFile).readAsStringSync(),
      ),
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
    // Don't write the logs to file on a normal run.
    expect(File(logFile).existsSync(), isFalse);
  });
}

String _filter(String input) {
  return input
      .replaceAll(d.sandbox, r'$SANDBOX')
      .replaceAll(Platform.pathSeparator, '/')
      .replaceAll(Platform.operatingSystem, r'$OS')
      .replaceAll(globalServer.port.toString(), r'$PORT')
      .replaceAll(
        RegExp(r'^Created:(.*)$', multiLine: true),
        r'Created: $TIME',
      )
      .replaceAll(
        RegExp(r'Generated by pub on (.*)$', multiLine: true),
        r'Generated by pub on $TIME',
      )
      .replaceAll(
        RegExp(r'X-Pub-Session-ID(.*)$', multiLine: true),
        r'X-Pub-Session-ID: $ID',
      )
      .replaceAll(
        RegExp(r'took (.*)$', multiLine: true),
        r'took: $TIME',
      )
      .replaceAll(
        RegExp(r'date: (.*)$', multiLine: true),
        r'date: $TIME',
      )
      .replaceAll(
        RegExp(r'Creating (.*) from stream\.$', multiLine: true),
        r'Creating $FILE from stream',
      )
      .replaceAll(
        RegExp(r'Created (.*) from stream\.$', multiLine: true),
        r'Created $FILE from stream',
      )
      .replaceAll(
        RegExp(r'Renaming directory $SANDBOX/cache/_temp/(.*?) to',
            multiLine: true),
        r'Renaming directory $SANDBOX/cache/_temp/',
      )
      .replaceAll(
        RegExp(r'Extracting .tar.gz stream to (.*?)$', multiLine: true),
        r'Extracting .tar.gz stream to $DIR',
      )
      .replaceAll(
        RegExp(r'Extracted .tar.gz to (.*?)$', multiLine: true),
        r'Extracted .tar.gz to $DIR',
      )
      .replaceAll(
        RegExp(r'Reading binary file (.*?)$', multiLine: true),
        r'Reading binary file $FILE.',
      )
      .replaceAll(
        RegExp(r'Deleting directory (.*)$', multiLine: true),
        r'Deleting directory $DIR',
      )
      .replaceAll(
        RegExp(r'Deleting directory (.*)$', multiLine: true),
        r'Deleting directory $DIR',
      )
      .replaceAll(
        RegExp(r'Resolving dependencies finished (.*)$', multiLine: true),
        r'Resolving dependencies finished ($TIME)',
      )
      .replaceAll(
        RegExp(r'Created temp directory (.*)$', multiLine: true),
        r'Created temp directory $DIR',
      )
      .replaceAll(
        RegExp(r'Renaming directory (.*)$', multiLine: true),
        r'Renaming directory $A to $B',
      )
      .replaceAll(
        RegExp(r'"_fetchedAt":"(.*)"}$', multiLine: true),
        r'"_fetchedAt": "$TIME"}',
      )
      .replaceAll(
        RegExp(r'"generated": "(.*)",$', multiLine: true),
        r'"generated": "$TIME",',
      );
}
