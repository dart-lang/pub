// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub/src/exit_codes.dart';
import 'package:pub/src/io.dart' show EnvironmentKeys;
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

import '../descriptor.dart' as d;
import '../golden_file.dart';
import '../test_pub.dart';
import 'ensure_pubspec_resolved.dart';
import 'get_executable_for_command.dart';

const _commandRunner = 'tool/test-bin/pub_command_runner.dart';

late String snapshot;

final logFile = p.join(d.sandbox, cachePath, 'log', 'pub_log.txt');

/// Runs `dart tool/test-bin/pub_command_runner.dart [args]` and appends the output to [buffer].
Future<void> runEmbeddingToBuffer(
  List<String> args,
  StringBuffer buffer, {
  String? workingDirectory,
  Map<String, String?>? environment,
  dynamic exitCode = 0,
}) async {
  final combinedEnvironment = getPubTestEnvironment();
  (environment ?? {}).forEach((key, value) {
    if (value == null) {
      combinedEnvironment.remove(key);
    } else {
      combinedEnvironment[key] = value;
    }
  });
  final process = await TestProcess.start(
    Platform.resolvedExecutable,
    ['--enable-asserts', snapshot, ...args],
    environment: combinedEnvironment,
    workingDirectory: workingDirectory,
  );
  await process.shouldExit(exitCode);

  final stdoutLines = await process.stdout.rest.toList();
  final stderrLines = await process.stderr.rest.toList();

  buffer.writeln(
    [
      '\$ $_commandRunner ${args.join(' ')}',
      if (stdoutLines.isNotEmpty) _filter(stdoutLines.join('\n')),
      if (stderrLines.isNotEmpty)
        _filter(
          stderrLines.join('\n'),
        ).replaceAll(RegExp('^', multiLine: true), '[E] '),
    ].join('\n'),
  );
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
    snapshot = p.join(tempDir.path, 'command_runner.dart.snapshot');
    final r = Process.runSync(Platform.resolvedExecutable, [
      '--snapshot=$snapshot',
      _commandRunner,
    ]);
    expect(r.exitCode, 0, reason: r.stderr as String);
  });

  tearDownAll(() {
    File(snapshot).parent.deleteSync(recursive: true);
  });

  testWithGolden('run works, though hidden', (ctx) async {
    await servePackages();
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir('bin', [
        d.file('main.dart', '''
import 'dart:io';
main() {
  print('Hi');
  exit(123);
}
'''),
      ]),
    ]).create();
    await ctx.runEmbedding(['pub', 'get'], workingDirectory: d.path(appPath));
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
      await d.appDir(dependencies: {'foo': 'any'}).create();

      // TODO(sigurdm) This logs the entire verbose trace to a golden file.
      //
      // This is fragile, and can break for all sorts of small reasons. We think
      // this might be worth while having to have at least minimal testing of
      // the verbose stack trace.
      //
      // But if you, future contributor, think this test is annoying: feel free
      // to remove it, or rewrite it to filter out the stack-trace itself, only
      // testing for creation of the file.
      //
      //  It is a fragile test, and we acknowledge that it's usefulness can be
      //  debated...
      await context.runEmbedding([
        'pub',
        '--verbose',
        'get',
      ], workingDirectory: d.path(appPath));
      context.expectNextSection(_filter(File(logFile).readAsStringSync()));
      await d.dir('empty').create();
      await context.runEmbedding(
        ['pub', 'fail'],
        workingDirectory: d.path('empty'),
        exitCode: 1,
      );
      context.expectNextSection(_filter(File(logFile).readAsStringSync()));
    },
  );

  test('`embedding --verbose pub` is verbose', () async {
    await servePackages();
    final buffer = StringBuffer();
    await runEmbeddingToBuffer(['--verbose', 'pub', 'logout'], buffer);
    expect(buffer.toString(), contains('FINE: Pub 3.1.2+3'));
  });

  testWithGolden('--help', (context) async {
    await servePackages();
    await context.runEmbedding([
      'pub',
      '--help',
    ], workingDirectory: d.path('.'));
  });

  testWithGolden('--color forces colors', (context) async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');
    server.serve('foo', '2.0.0');
    await d.appDir(dependencies: {'foo': '^1.0.0'}).create();
    await context.runEmbedding(
      ['pub', '--no-color', 'get'],
      environment: getPubTestEnvironment(),
      workingDirectory: d.path(appPath),
    );
    await context.runEmbedding(
      ['pub', '--color', 'get'],
      workingDirectory: d.path(appPath),
      environment: getPubTestEnvironment(),
    );
  });

  testWithGolden('Compilation errors are only printed once', (context) async {
    await servePackages();
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir('bin', [d.file('syntax_error.dart', 'main() => print("hi")')]),
    ]).create();
    await context.runEmbedding(
      ['run', ':syntax_error'],
      environment: getPubTestEnvironment(),
      workingDirectory: d.path(appPath),
      exitCode: isNot(0),
    );
  });

  test('`embedding run` does `pub get` if sdk updated', () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '^2.18.0'},
        'dependencies': {'foo': '^1.0.0'},
      }),
      d.dir('bin', [d.file('myapp.dart', 'main() {print(42);}')]),
    ]).create();

    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      pubspec: {
        'environment': {'sdk': '^2.18.0'},
      },
    );

    await pubGet(environment: {'_PUB_TEST_SDK_VERSION': '2.18.3'});
    // Deleting the version-listing cache will cause it to be refetched, and the
    // warning will happen.
    File(
      p.join(globalServer.cachingPath, '.cache', 'foo-versions.json'),
    ).deleteSync();
    server.serve(
      'foo',
      '1.0.1',
      pubspec: {
        'environment': {'sdk': '^2.18.0'},
      },
    );

    final buffer = StringBuffer();

    // Just changing the patch version should not trigger a pub get.
    await runEmbeddingToBuffer(
      ['--verbose', 'run', 'myapp'],
      buffer,
      workingDirectory: d.path(appPath),
      environment: {'_PUB_TEST_SDK_VERSION': '2.18.4'},
    );

    expect(
      buffer.toString(),
      allOf(contains('42'), isNot(contains('Resolving dependencies'))),
    );

    File(p.join(globalServer.cachingPath, '.cache', 'foo-versions.json'));
    buffer.clear();

    // Changing the minor version should.
    await runEmbeddingToBuffer(
      ['--verbose', 'run', 'myapp'],
      buffer,
      workingDirectory: d.path(appPath),
      environment: {'_PUB_TEST_SDK_VERSION': '2.19.3'},
    );
    expect(
      buffer.toString(),
      allOf(
        contains('42'),
        contains('Resolving dependencies'),
        contains('1.0.1 available'),
      ),
    );
  });

  test(
    '`embedding run` does not have output when successful and no terminal',
    () async {
      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependencies': {'foo': '^1.0.0'},
        }),
        d.dir('bin', [d.file('myapp.dart', 'main() {print(42);}')]),
      ]).create();

      final server = await servePackages();
      server.serve('foo', '1.0.0');

      final buffer = StringBuffer();
      await runEmbeddingToBuffer(
        ['run', 'myapp'],
        buffer,
        workingDirectory: d.path(appPath),
        environment: {EnvironmentKeys.forceTerminalOutput: '0'},
      );

      expect(
        buffer.toString(),
        allOf(isNot(contains('Resolving dependencies...')), contains('42')),
      );
    },
  );
  test(
    '`embedding run` outputs info when successful and has a terminal',
    () async {
      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependencies': {'foo': '^1.0.0'},
        }),
        d.dir('bin', [d.file('myapp.dart', 'main() {print(42);}')]),
      ]).create();

      final server = await servePackages();
      server.serve('foo', '1.0.0');

      final buffer = StringBuffer();
      await runEmbeddingToBuffer(
        ['run', 'myapp'],
        buffer,
        workingDirectory: d.path(appPath),
        environment: {EnvironmentKeys.forceTerminalOutput: '1'},
      );
      expect(
        buffer.toString(),
        allOf(contains('Resolving dependencies'), contains('42')),
      );
    },
  );

  test('`embedding run` does not recompile executables '
      'from packages depending on sdk packages', () async {
    final server = await servePackages();
    server.serve(
      'hosted',
      '1.0.0',
      deps: {
        'foo': {'sdk': 'flutter'},
      },
      contents: [
        d.dir('bin', [d.file('hosted.dart', 'main() {print(42);}')]),
      ],
    );
    await d.dir('flutter', [
      d.dir('bin', [
        d.dir('cache', [
          d.file('flutter.version.json', '{"flutterVersion": "1.2.3"}'),
        ]),
      ]),
      d.dir('packages', [
        d.dir('foo', [d.libPubspec('foo', '1.2.3')]),
      ]),
    ]).create();

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependencies': {'hosted': '^1.0.0'},
      }),
    ]).create();

    final buffer = StringBuffer();
    await runEmbeddingToBuffer(
      ['run', 'hosted'],
      buffer,
      workingDirectory: d.path(appPath),
      environment: {
        'FLUTTER_ROOT': p.join(d.sandbox, 'flutter'),
        EnvironmentKeys.forceTerminalOutput: '1',
      },
    );

    expect(
      buffer.toString(),
      allOf(contains('Built hosted:hosted'), contains('42')),
    );

    final buffer2 = StringBuffer();
    await runEmbeddingToBuffer(
      ['run', 'hosted'],
      buffer2,
      workingDirectory: d.path(appPath),
      environment: {
        'FLUTTER_ROOT': p.join(d.sandbox, 'flutter'),
        EnvironmentKeys.forceTerminalOutput: '1',
      },
    );
    expect(
      buffer2.toString(),
      allOf(isNot(contains('Built hosted:hosted')), contains('42')),
    );
  });

  test('"pkg" and "packages" will trigger a suggestion of "pub"', () async {
    await servePackages();
    await d.appDir().create();
    for (final command in ['pkg', 'packages']) {
      final buffer = StringBuffer();
      await runEmbeddingToBuffer(
        [command, 'get'],
        buffer,
        workingDirectory: d.path(appPath),
        exitCode: USAGE,
      );
      expect(
        buffer.toString(),
        allOf(contains('Did you mean one of these?'), contains('  pub')),
      );
    }
  });

  testEnsurePubspecResolved();
  testGetExecutableForCommand();
}

String _filter(String input) {
  return input
      .replaceAll(
        RegExp(
          RegExp.escape(p.toUri(d.sandbox).toString()),
          caseSensitive: false,
        ),
        r'file://$SANDBOX',
      )
      .replaceAll(d.sandbox, r'$SANDBOX')
      .replaceAll(Platform.pathSeparator, '/')
      .replaceAll(Platform.operatingSystem, r'$OS')
      .replaceAll(globalServer.port.toString(), r'$PORT')
      .replaceAll(RegExp(r'^Created:(.*)$', multiLine: true), r'Created: $TIME')
      .replaceAll(
        RegExp(r'Generated by pub on (.*)$', multiLine: true),
        r'Generated by pub on $TIME',
      )
      .replaceAll(
        RegExp(r'X-Pub-Session-ID(.*)$', multiLine: true),
        r'X-Pub-Session-ID: $ID',
      )
      .replaceAll(RegExp(r'took (.*)$', multiLine: true), r'took: $TIME')
      .replaceAll(RegExp(r'date: (.*)$', multiLine: true), r'date: $TIME')
      .replaceAll(
        RegExp(r'Creating (.*) from stream\.$', multiLine: true),
        r'Creating $FILE from stream',
      )
      .replaceAll(
        RegExp(r'Created (.*) from stream\.$', multiLine: true),
        r'Created $FILE from stream',
      )
      .replaceAll(
        RegExp(
          r'Renaming directory $SANDBOX/cache/_temp/(.*?) to',
          multiLine: true,
        ),
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
        RegExp(r'Downloading packages finished (.*)$', multiLine: true),
        r'Downloading packages finished ($TIME)',
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
      )
      .replaceAll(
        RegExp(
          r'( |^)(/|[A-Z]:)(.*)/tool/test-bin/pub_command_runner.dart',
          multiLine: true,
        ),
        r' tool/test-bin/pub_command_runner.dart',
      )
      .replaceAll(RegExp(r'[ ]{4,}', multiLine: true), r'   ')
      .replaceAll(RegExp(r' [\d]+:[\d]+ +', multiLine: true), r' $LINE:$COL ')
      .replaceAll(
        RegExp(r'Writing \d+ characters', multiLine: true),
        r'Writing $N characters',
      )
      .replaceAll(
        RegExp(r'x-goog-hash(.*)$', multiLine: true),
        r'x-goog-hash: $CHECKSUM_HEADER',
      )
      .replaceAll(
        RegExp(
          r'Computed checksum \d+ for foo 1.0.0 with expected CRC32C of '
          r'\d+\.',
          multiLine: true,
        ),
        r'Computed checksum $CRC32C for foo 1.0.0 with expected CRC32C of '
        r'$CRC32C.',
      )
      .replaceAll(
        RegExp(r'sha256: "?[0-9a-f]{64}"?', multiLine: true),
        r'sha256: $SHA256',
      )
      .replaceAll(
        RegExp(r'"archive_sha256":"[0-9a-f]{64}"', multiLine: true),
        r'"archive_sha256":"$SHA256"',
      )
      .replaceAll(
        RegExp(r'active_roots/[0-9a-f]{2}/[0-9a-f]{62}', multiLine: true),
        r'active_roots/$HH/$HASH',
      )
      /// TODO(sigurdm): This hack suppresses differences in stack-traces
      /// between dart 2.17 and 2.18. Remove when 2.18 is stable.
      .replaceAllMapped(
        RegExp(
          r'(^(.*)pub/src/command.dart \$LINE:\$COL(.*)$)\n\1',
          multiLine: true,
        ),
        (match) => match[1]!,
      );
}
