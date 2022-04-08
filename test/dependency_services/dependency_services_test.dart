// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub/src/io.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:shelf/shelf.dart' as shelf;
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
  /// Returns the stdout.
  Future<String> runDependencyServices(List<String> args,
      {String? stdin}) async {
    final buffer = StringBuffer();
    buffer.writeln('## Section ${args.join(' ')}');
    final process = await Process.start(
      Platform.resolvedExecutable,
      [
        snapshot,
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
    final outLines = outputLines(process.stdout);
    final errLines = outputLines(process.stderr);
    final exitCode = await process.exitCode;

    final pipe = stdin == null ? '' : ' echo ${escapeShellArgument(stdin)} |';
    buffer.writeln([
      '\$$pipe dependency_services ${args.map(escapeShellArgument).join(' ')}',
      ...await outLines,
      ...(await errLines).map((e) => '[STDERR] $e'),
      if (exitCode != 0) '[EXIT CODE] $exitCode',
    ].join('\n'));

    expectNextSection(buffer.toString());
    return (await outLines).join('\n');
  }
}

Future<Iterable<String>> outputLines(Stream<List<int>> stream) async {
  final s = await utf8.decodeStream(stream);
  if (s.isEmpty) return [];
  return filterUnstableLines(s.split('\n'));
}

Future<void> listReportApply(
  GoldenTestContext context,
  List<_PackageVersion> upgrades, {
  void Function(Map)? reportAssertions,
}) async {
  manifestAndLockfile(context);
  await context.runDependencyServices(['list']);
  final report = await context.runDependencyServices(['report']);
  if (reportAssertions != null) {
    reportAssertions(json.decode(report));
  }
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
    final server = (await servePackages())
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
    server.dontAllowDownloads();
    await listReportApply(context, [
      _PackageVersion('foo', '2.2.3'),
      _PackageVersion('transitive', null)
    ], reportAssertions: (report) {
      expect(
        findChangeVersion(report, 'singleBreaking', 'foo'),
        '2.2.3',
      );
      expect(
        findChangeVersion(report, 'singleBreaking', 'transitive'),
        null,
      );
    });
  });

  testWithGolden('Compatible', (context) async {
    final server = (await servePackages())
      ..serve('foo', '1.2.3')
      ..serve('foo', '2.2.3')
      ..serve('bar', '1.2.3')
      ..serve('bar', '2.2.3')
      ..serve('boo', '1.2.3');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {
          'foo': '^1.0.0',
          'bar': '^1.0.0',
          'boo': '^1.0.0',
        },
      })
    ]).create();
    await pubGet();
    server.serve('foo', '1.2.4');
    server.serve('boo', '1.2.4');

    server.dontAllowDownloads();

    await listReportApply(context, [
      _PackageVersion('foo', '1.2.4'),
    ], reportAssertions: (report) {
      expect(
        findChangeVersion(report, 'compatible', 'foo'),
        '1.2.4',
      );
    });
  });

  testWithGolden('Adding transitive', (context) async {
    final server = (await servePackages())
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
    server.dontAllowDownloads();

    await listReportApply(context, [
      _PackageVersion('foo', '2.2.3'),
      _PackageVersion('transitive', '1.0.0')
    ], reportAssertions: (report) {
      expect(
        findChangeVersion(report, 'singleBreaking', 'foo'),
        '2.2.3',
      );
      expect(
        findChangeVersion(report, 'singleBreaking', 'transitive'),
        '1.0.0',
      );
    });
  });

  testWithGolden('multibreaking', (context) async {
    final server = (await servePackages())
      ..serve('foo', '1.0.0')
      ..serve('bar', '1.0.0')
      ..serve('baz', '1.0.0');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {
          'foo': '^1.0.0',
          'bar': '^1.0.0',
          // Pinned version. See that the widened constraint is correct.
          'baz': '1.0.0',
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
      ..serve('baz', '1.1.0');

    server.dontAllowDownloads();

    await listReportApply(context, [
      _PackageVersion('foo', '3.0.1',
          constraint: VersionConstraint.parse('^3.0.0')),
      _PackageVersion('bar', '2.0.0')
    ], reportAssertions: (report) {
      expect(
        findChangeVersion(report, 'multiBreaking', 'foo'),
        '3.0.1',
      );
      expect(
        findChangeVersion(report, 'multiBreaking', 'bar'),
        '2.0.0',
      );
    });
  });
  testWithGolden('Relative paths are allowed', (context) async {
    // We cannot update path-dependencies, but they should be allowed.
    final server = await servePackages();
    server.serve('foo', '1.0.0');
    await d.dir('bar', [d.libPubspec('bar', '1.0.0')]).create();

    await d.appDir({
      'foo': '^1.0.0',
      'bar': {'path': '../bar'}
    }).create();
    await pubGet();
    server.serve('foo', '2.0.0');
    await listReportApply(context, [
      _PackageVersion('foo', '2.0.0',
          constraint: VersionConstraint.parse('^2.0.0')),
    ], reportAssertions: (report) {
      expect(
        findChangeVersion(report, 'multiBreaking', 'foo'),
        '2.0.0',
      );
    });
  });

  testWithGolden('Can update a git package', (context) async {
    await d.git('foo.git', [d.libPubspec('foo', '1.0.0')]).create();

    await d.appDir({
      'foo': {
        'git': {'url': '../foo.git'}
      }
    }).create();
    await pubGet();
    final secondVersion = d.git('foo.git', [d.libPubspec('foo', '2.0.0')]);
    await secondVersion.commit();
    final newRef = await secondVersion.revParse('HEAD');

    await listReportApply(context, [
      _PackageVersion('foo', newRef),
    ], reportAssertions: (report) {
      expect(
        findChangeVersion(report, 'compatible', 'foo'),
        newRef,
      );
    });
  });
}

dynamic findChangeVersion(dynamic json, String updateType, String name) {
  final dep = json['dependencies'].firstWhere((p) => p['name'] == 'foo');
  if (dep == null) return null;
  return dep[updateType].firstWhere((p) => p['name'] == name)['version'];
}

class _PackageVersion {
  String name;
  String? version;
  VersionConstraint? constraint;
  _PackageVersion(this.name, this.version, {this.constraint});

  Map<String, Object?> toJson() => {
        'name': name,
        'version': version,
        if (constraint != null) 'constraint': constraint.toString()
      };
}

extension on PackageServer {
  ///Check that nothing is downloaded.
  void dontAllowDownloads() {
    // This testing logic is a bit fragile, if we change the pattern for pattern
    // for the download URL then this will pass silently. There isn't much we
    // can / should do about it. Just accept the limitations, and remove it if
    // the test becomes useless.
    handle(RegExp(r'/.+\.tar\.gz'), (request) {
      return shelf.Response.notFound(
          'This test should not download archives! Requested ${request.url}');
    });
  }
}
