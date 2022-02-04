// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

import '../descriptor.dart' as d;
import '../golden_file.dart';
import '../test_pub.dart';

late String snapshot;
const _commandRunner = 'bin/dependency_services.dart';

String _filter(String input) {
  return input
      .replaceAll(p.toUri(d.sandbox).toString(), r'file://$SANDBOX')
      .replaceAll(d.sandbox, r'$SANDBOX')
      .replaceAll(Platform.pathSeparator, '/')
      .replaceAll(Platform.operatingSystem, r'$OS')
      .replaceAll(globalServer.port.toString(), r'$PORT');
}

/// Runs `dart tool/test-bin/pub_command_runner.dart [args]` and appends the output to [buffer].
Future<void> runDependencyServicesToBuffer(
  List<String> args,
  StringBuffer buffer, {
  String? workingDirectory,
  Map<String, String>? environment,
  dynamic exitCode = 0,
  String? stdin,
}) async {
  final process = await TestProcess.start(
    Platform.resolvedExecutable,
    ['--enable-asserts', snapshot, ...args],
    environment: {
      ...getPubTestEnvironment(),
      ...?environment,
    },
    workingDirectory: workingDirectory ?? p.join(d.sandbox, appPath),
  );
  if (stdin != null) {
    process.stdin.write(stdin);
    await process.stdin.flush();
    await process.stdin.close();
  }
  await process.shouldExit(exitCode);

  buffer.writeln([
    '\$ $_commandRunner ${args.join(' ')}',
    ...await process.stdout.rest.map(_filter).toList(),
    ...await process.stderr.rest.map((e) => '[E] ${_filter(e)}').toList(),
  ].join('\n'));
  buffer.write('\n');
}

Future<void> pipeline(
  String name,
  List<_PackageVersion> upgrades,
  GoldenTestContext context,
) async {
  final buffer = StringBuffer();
  await runDependencyServicesToBuffer(['list'], buffer);
  await runDependencyServicesToBuffer(['report'], buffer);

  final input = json.encode({
    'dependencyChanges': upgrades,
  });

  await runDependencyServicesToBuffer(['apply'], buffer, stdin: input);
  void catIntoBuffer(String path) {
    buffer.writeln('$path:');
    buffer.writeln(File(p.join(d.sandbox, path)).readAsStringSync());
  }

  catIntoBuffer(p.join(appPath, 'pubspec.yaml'));
  catIntoBuffer(p.join(appPath, 'pubspec.lock'));
  context.expectNextSection(
    buffer.toString().replaceAll(RegExp(r'localhost:\d+'), 'localhost:<port>'),
  );
}

Future<void> main() async {
  setUpAll(() async {
    final tempDir = Directory.systemTemp.createTempSync();
    snapshot = p.join(tempDir.path, 'dependency_services.dart.snapshot');
    final r = Process.runSync(
        Platform.resolvedExecutable, ['--snapshot=$snapshot', _commandRunner]);
    expect(r.exitCode, 0, reason: r.stderr);
  });
  testWithGolden('Removing transitive', (context) async {
    (await servePackages())
      ..serve('foo', '1.2.3', deps: {'transitive': '^1.0.0'})
      ..serve('foo', '2.2.3')
      ..serve('transitive', '1.0.0');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {
          'foo': '^1.0.0',
        },
      })
    ]).create();
    await pubGet();
    await pipeline(
      'removing_transitive',
      [
        _PackageVersion('foo', Version.parse('2.2.3')),
        _PackageVersion('transitive', null)
      ],
      context,
    );
  });

  testWithGolden('Adding transitive', (context) async {
    (await servePackages())
      ..serve('foo', '1.2.3')
      ..serve('foo', '2.2.3', deps: {'transitive': '^1.0.0'})
      ..serve('transitive', '1.0.0');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {
          'foo': '^1.0.0',
        },
      })
    ]).create();
    await pubGet();
    await pipeline(
      'adding_transitive',
      [
        _PackageVersion('foo', Version.parse('2.2.3')),
        _PackageVersion('transitive', Version.parse('1.0.0'))
      ],
      context,
    );
  });
}

class _PackageVersion {
  String name;
  Version? version;
  _PackageVersion(this.name, this.version);

  Map<String, Object?> toJson() => {
        'name': name,
        'version': version?.toString(),
      };
}
