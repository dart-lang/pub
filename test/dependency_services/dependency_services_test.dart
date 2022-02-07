// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub/src/dart.dart';
import 'package:pub/src/io.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../golden_file.dart';
import '../test_pub.dart';

void manifestAndLockfile(GoldenTestContext context) {
  String catFile(String filename) {
    final contents = filterUnstableLines(
        File(p.join(d.sandbox, appPath, filename)).readAsLinesSync());

    return '''
\$ cat $filename
${contents.join('\n')}''';
  }

  context.expectNextSection('''
${catFile('pubspec.yaml')}
${catFile('pubspec.lock')}
''');
}

late final String snapshot;

extension on GoldenTestContext {
  Future<void> runDependencyServices(List<String> args, {String? stdin}) async {
    final buffer = StringBuffer();
    buffer.writeln('## Section ${args.join(' ')}');
    final process = await Process.start(
      Platform.resolvedExecutable,
      [
        await snapshot,
        ...args,
      ],
      environment: getPubTestEnvironment(),
      workingDirectory: p.join(d.sandbox, appPath),
    );
    if (stdin != null) {
      process.stdin.write(stdin);
      await process.stdin.flush();
      await process.stdin.close();
    }
    final exitCode = await process.exitCode;

    final pipe = stdin == null ? '' : ' echo ${protectArgument(stdin)} |';
    buffer.writeln([
      '\$$pipe dependency_services ${args.map(protectArgument).join(' ')}',
      ...await outputLines(process.stdout),
      ...(await outputLines(process.stderr)).map((e) => '[STDERR] $e'),
      if (exitCode != 0) '[EXIT CODE] $exitCode',
    ].join('\n'));

    expectNextSection(buffer.toString());
  }
}

Future<Iterable<String>> outputLines(Stream<List<int>> stream) async {
  final s = await utf8.decodeStream(stream);
  if (s.isEmpty) return [];
  return filterUnstableLines(s.split('\n'));
}

Future<void> listReportApply(
  GoldenTestContext context,
  List<_PackageVersion> upgrades,
) async {
  manifestAndLockfile(context);
  await context.runDependencyServices(['list']);
  await context.runDependencyServices(['report']);

  final input = json.encode({
    'dependencyChanges': upgrades,
  });

  await context.runDependencyServices(['apply'], stdin: input);
  manifestAndLockfile(context);
}

Future<void> main() async {
  setUpAll(() async {
    final tempDir = Directory.systemTemp.createTempSync();
    snapshot = p.join(tempDir.path, 'dependency_services.dart.snapshot');
    final r = Process.runSync(Platform.resolvedExecutable, [
      '--snapshot=$snapshot',
      p.join('bin', 'dependency_services.dart'),
    ]);
    expect(r.exitCode, 0, reason: r.stderr);
  });

  tearDownAll(() {
    File(snapshot).parent.deleteSync(recursive: true);
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
    await listReportApply(context, [
      _PackageVersion('foo', Version.parse('2.2.3')),
      _PackageVersion('transitive', null)
    ]);
  });

  testWithGolden('Compatible', (context) async {
    final server = (await servePackages())
      ..serve('foo', '1.2.3')
      ..serve('foo', '2.2.3')
      ..serve('bar', '1.2.3')
      ..serve('bar', '2.2.3');
    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {
          'foo': '^1.0.0',
          'bar': '^1.0.0',
        },
      })
    ]).create();
    await pubGet();
    server.serve('foo', '1.2.4');
    await listReportApply(context, [
      _PackageVersion('foo', Version.parse('1.2.3')),
      _PackageVersion('transitive', null)
    ]);
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
    await listReportApply(context, [
      _PackageVersion('foo', Version.parse('2.2.3')),
      _PackageVersion('transitive', Version.parse('1.0.0'))
    ]);
  });

  testWithGolden('multibreaking', (context) async {
    final server = (await servePackages())
      ..serve('foo', '1.0.0')
      ..serve('bar', '1.0.0');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {
          'foo': '^1.0.0',
          'bar': '^1.0.0',
        },
      })
    ]).create();
    await pubGet();
    server
      ..serve('foo', '1.5.0') // compatible
      ..serve('foo', '2.0.0') // single breaking
      ..serve('foo', '3.0.0', deps: {'bar': '^2.0.0'}) // multi breaking
      ..serve('foo', '3.0.1', deps: {'bar': '^2.0.0'})
      ..serve('bar', '2.0.0', deps: {'foo': '^3.0.0'})
      ..serve('transitive', '1.0.0');
    await listReportApply(context, [
      _PackageVersion('foo', Version.parse('3.0.1'),
          constraint: VersionConstraint.parse('^3.0.0')),
      _PackageVersion('bar', Version.parse('2.0.0'))
    ]);
  });
}

class _PackageVersion {
  String name;
  Version? version;
  VersionConstraint? constraint;
  _PackageVersion(this.name, this.version, {this.constraint});

  Map<String, Object?> toJson() => {
        'name': name,
        'version': version?.toString(),
        if (constraint != null) 'constraint': constraint.toString()
      };
}
