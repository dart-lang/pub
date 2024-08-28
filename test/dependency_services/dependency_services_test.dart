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
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import '../descriptor.dart' as d;
import '../descriptor.dart';
import '../golden_file.dart';
import '../test_pub.dart';

void manifestAndLockfile(GoldenTestContext context, List<String> workspace) {
  String catFile(String filename) {
    final path = p.join(d.sandbox, appPath, filename);
    final normalizedFilename = p.posix.joinAll(p.split(p.normalize(filename)));
    if (File(path).existsSync()) {
      final contents = File(path).readAsLinesSync().map(filterUnstableText);

      return '''
\$ cat $normalizedFilename
${contents.join('\n')}''';
    } else {
      return '''
\$ cat $normalizedFilename
No such file $normalizedFilename.''';
    }
  }

  context.expectNextSection('''
${workspace.map((path) => catFile(p.join(path, 'pubspec.yaml'))).join('\n')}
${catFile('pubspec.lock')}
''');
}

late final String snapshot;

extension on GoldenTestContext {
  /// Returns the stdout.
  Future<String> runDependencyServices(
    List<String> args, {
    String stdin = '',
    Map<String, String>? environment,
  }) async {
    final buffer = StringBuffer();
    buffer.writeln('## Section ${args.join(' ')}');
    final process = await Process.start(
      Platform.resolvedExecutable,
      [
        '--enable-asserts',
        snapshot,
        '--verbose',
        ...args,
      ],
      environment: {
        ...getPubTestEnvironment(),
        '_PUB_TEST_DEFAULT_HOSTED_URL': globalServer.url,
        ...?environment,
      },
      workingDirectory: p.join(d.sandbox, appPath),
    );
    process.stdin.write(stdin);
    await process.stdin.flush();
    await process.stdin.close();

    final outLines = outputLines(process.stdout);
    final errLines = outputLines(process.stderr);
    final exitCode = await process.exitCode;

    final pipe = ' echo ${filterUnstableText(escapeShellArgument(stdin))} |';
    final argString = args.map(escapeShellArgument).join(' ');
    buffer.writeln(
      [
        '\$$pipe dependency_services $argString',
        ...await outLines,
        ...(await errLines).map((e) => '[STDERR] $e'),
        if (exitCode != 0) '[EXIT CODE] $exitCode',
      ].join('\n'),
    );

    expectNextSection(buffer.toString());
    return (await outLines).join('\n');
  }
}

Future<Iterable<String>> outputLines(Stream<List<int>> stream) async {
  final s = await utf8.decodeStream(stream);
  if (s.isEmpty) return [];
  return s.split('\n').map(filterUnstableText);
}

Future<void> _listReportApply(
  GoldenTestContext context,
  List<_PackageVersion> upgrades, {
  List<String> workspace = const ['.'],
  void Function(Map)? reportAssertions,
  Map<String, String>? environment,
}) async {
  manifestAndLockfile(context, workspace);
  await context.runDependencyServices(['list'], environment: environment);
  final report =
      await context.runDependencyServices(['report'], environment: environment);
  if (reportAssertions != null) {
    reportAssertions(json.decode(report) as Map);
  }
  final input = json.encode({
    'dependencyChanges': upgrades,
  });

  await context.runDependencyServices(
    ['apply'],
    stdin: input,
    environment: environment,
  );
  manifestAndLockfile(context, workspace);
}

Future<void> _reportWithForbidden(
  GoldenTestContext context,
  Map<String, List<String>> disallowedVersions, {
  void Function(Map)? resultAssertions,
  String? targetPackage,
}) async {
  manifestAndLockfile(context, ['.']);
  final input = json.encode({
    'target': targetPackage,
    'disallowed': [
      for (final e in disallowedVersions.entries)
        {
          'name': e.key,
          'url': globalServer.url,
          'versions': e.value.map((d) => {'range': d}).toList(),
        },
    ],
  });
  final report = await context.runDependencyServices(['report'], stdin: input);
  if (resultAssertions != null) {
    resultAssertions(json.decode(report) as Map);
  }

  // await context.runDependencyServices(['apply'], stdin: input);
  manifestAndLockfile(context, ['.']);
}

Future<void> main() async {
  setUpAll(() async {
    final tempDir = Directory.systemTemp.createTempSync();
    snapshot = p.join(tempDir.path, 'dependency_services.dart.snapshot');
    final r = Process.runSync(Platform.resolvedExecutable, [
      '--snapshot=$snapshot',
      p.join('bin', 'dependency_services.dart'),
    ]);
    expect(r.exitCode, 0, reason: r.stderr as String);
  });

  tearDownAll(() {
    File(snapshot).parent.deleteSync(recursive: true);
  });

  testWithGolden('Removing transitive', (context) async {
    final server = (await servePackages())
      ..serve('foo', '1.2.3', deps: {'transitive': '^1.0.0'})
      ..serve('foo', '2.2.3')
      ..serve('transitive', '1.0.0')
      ..serveContentHashes = true;

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {
          'foo': '^1.0.0',
        },
      }),
    ]).create();
    await pubGet();
    server.dontAllowDownloads();
    await _listReportApply(
      context,
      [_PackageVersion('foo', '2.2.3'), _PackageVersion('transitive', null)],
      reportAssertions: (report) {
        expect(
          findChangeVersion(report, 'singleBreaking', 'foo'),
          '2.2.3',
        );
        expect(
          findChangeVersion(report, 'singleBreaking', 'transitive'),
          null,
        );
      },
    );
  });

  testWithGolden('Ignoring version', (context) async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {
          'foo': '^1.0.0',
        },
      }),
    ]).create();
    await pubGet();

    server.serve('foo', '1.0.1'); // should get this.
    server.serve('foo', '1.0.2'); // ignored
    server.serve('foo', '1.0.3', deps: {'transitive': '1.0.0'});
    server.serve('transitive', '1.0.0'); // ignored
    await _reportWithForbidden(
      context,
      {
        'foo': ['1.0.2'],
        'transitive': ['1.0.0'],
      },
      resultAssertions: (report) {
        expect(
          findChangeVersion(report, 'compatible', 'foo'),
          '1.0.1',
        );
      },
    );
  });

  testWithGolden('No pubspec.lock', (context) async {
    final server = (await servePackages())
      ..serve('foo', '1.2.3', deps: {'transitive': '^1.0.0'})
      ..serve('foo', '2.2.3')
      ..serve('transitive', '1.0.0')
      ..serveContentHashes = true;

    await d.git('bar.git', [d.libPubspec('bar', '1.0.0')]).create();

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {
          'foo': '^1.0.0',
          'bar': {
            'git': {'url': '../bar.git'},
          },
        },
      }),
    ]).create();

    server.dontAllowDownloads();
    await _listReportApply(
      context,
      [
        _PackageVersion('foo', '2.2.3'),
        _PackageVersion('transitive', null),
      ],
    );
  });

  testWithGolden('Compatible', (context) async {
    final server = (await servePackages())
      ..serve('foo', '1.2.3')
      ..serve('foo', '2.2.3')
      ..serve('bar', '1.2.3')
      ..serve('bar', '2.2.3')
      ..serve('boo', '1.2.3')
      ..serveContentHashes = true;

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {
          'foo': '^1.0.0',
          'bar': '^1.0.0',
          'boo': '^1.0.0',
        },
      }),
    ]).create();
    await pubGet();
    server.serve('foo', '1.2.4');
    server.serve('boo', '1.2.4');

    server.dontAllowDownloads();

    await _listReportApply(
      context,
      [
        _PackageVersion('foo', '1.2.4'),
      ],
      reportAssertions: (report) {
        expect(
          findChangeVersion(report, 'compatible', 'foo'),
          '1.2.4',
        );
      },
    );
  });

  testWithGolden('Preserves no content-hashes', (context) async {
    final server = (await servePackages())
      ..serve('foo', '1.2.3')
      ..serve('foo', '2.2.3')
      ..serve('bar', '1.2.3')
      ..serve('bar', '2.2.3')
      ..serve('boo', '1.2.3')
      ..serveContentHashes = true;

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {
          'foo': '^1.0.0',
          'bar': '^1.0.0',
          'boo': '^1.0.0',
        },
      }),
    ]).create();
    await pubGet();
    final lockFile = File(path(p.join(appPath, 'pubspec.lock')));
    final lockFileYaml = YamlEditor(
      lockFile.readAsStringSync(),
    );
    for (final p in (lockFileYaml.parseAt(['packages']) as YamlMap).entries) {
      lockFileYaml.remove(['packages', p.key, 'description', 'sha256']);
    }
    lockFile.writeAsStringSync(lockFileYaml.toString());

    server.serve('foo', '1.2.4');
    server.serve('boo', '1.2.4');

    server.dontAllowDownloads();

    await _listReportApply(context, [
      _PackageVersion('foo', '1.2.4'),
    ]);
  });

  testWithGolden('Preserves pub.dartlang.org as hosted url', (context) async {
    final server = (await servePackages())
      ..serve(r'foo', '1.2.3')
      ..serve(r'bar', '1.2.3')
      ..serveContentHashes = true;

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {
          'foo': '^1.0.0',
          'bar': '^1.0.0',
        },
      }),
    ]).create();
    await pubGet();
    final lockFile = File(path(p.join(appPath, 'pubspec.lock')));
    final lockFileYaml = YamlEditor(
      lockFile.readAsStringSync(),
    );
    for (final p in (lockFileYaml.parseAt(['packages']).value as Map).entries) {
      lockFileYaml.update(
        ['packages', p.key, 'description', 'url'],
        'https://pub.dartlang.org',
      );
    }
    lockFile.writeAsStringSync(lockFileYaml.toString());

    server.serve('foo', '1.2.4');
    server.serve('boo', '1.2.4');

    await _listReportApply(
      context,
      [
        _PackageVersion('foo', '1.2.4'),
      ],
    );
  });

  testWithGolden('Adding transitive', (context) async {
    final server = (await servePackages())
      ..serve('foo', '1.2.3')
      ..serve('foo', '2.2.3', deps: {'transitive': '^1.0.0'})
      ..serve('transitive', '1.0.0')
      ..serveContentHashes = true;

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {
          'foo': '^1.0.0',
        },
      }),
    ]).create();
    await pubGet();
    server.dontAllowDownloads();

    await _listReportApply(
      context,
      [_PackageVersion('foo', '2.2.3'), _PackageVersion('transitive', '1.0.0')],
      reportAssertions: (report) {
        expect(
          findChangeVersion(report, 'singleBreaking', 'foo'),
          '2.2.3',
        );
        expect(
          findChangeVersion(report, 'singleBreaking', 'transitive'),
          '1.0.0',
        );
      },
    );
  });

  testWithGolden('multibreaking', (context) async {
    final server = (await servePackages())
      ..serve('foo', '1.0.0')
      ..serve('bar', '1.0.0')
      ..serve('baz', '1.0.0')
      ..serveContentHashes = true;

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {
          'foo': '^1.0.0',
          'bar': '^1.0.0',
          // Pinned version. See that the widened constraint is correct.
          'baz': '1.0.0',
        },
      }),
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

    await _listReportApply(
      context,
      [
        _PackageVersion(
          'foo',
          '3.0.1',
          constraint: VersionConstraint.parse('^3.0.0'),
        ),
        _PackageVersion('bar', '2.0.0'),
      ],
      reportAssertions: (report) {
        expect(
          findChangeVersion(report, 'multiBreaking', 'foo'),
          '3.0.1',
        );
        expect(
          findChangeVersion(report, 'multiBreaking', 'bar'),
          '2.0.0',
        );
      },
    );
  });
  testWithGolden('Relative paths are allowed', (context) async {
    // We cannot update path-dependencies, but they should be allowed.
    final server = await servePackages();
    server.serve('foo', '1.0.0');
    await d.dir('bar', [d.libPubspec('bar', '1.0.0')]).create();

    await d.appDir(
      dependencies: {
        'foo': '^1.0.0',
        'bar': {'path': '../bar'},
      },
    ).create();
    await pubGet();
    server.serve('foo', '2.0.0');
    await _listReportApply(
      context,
      [
        _PackageVersion(
          'foo',
          '2.0.0',
          constraint: VersionConstraint.parse('^2.0.0'),
        ),
      ],
      reportAssertions: (report) {
        expect(
          findChangeVersion(report, 'multiBreaking', 'foo'),
          '2.0.0',
        );
      },
    );
  });

  testWithGolden('Can update a git package', (context) async {
    await servePackages();
    await d.git('foo.git', [d.libPubspec('foo', '1.0.0')]).create();
    await d.git('bar.git', [d.libPubspec('bar', '1.0.0')]).create();

    await d.appDir(
      dependencies: {
        'foo': {
          'git': {'url': '../foo.git'},
        },
        'bar': {
          // A git dependency with a version constraint.
          'git': {'url': '../bar.git'},
          'version': '^1.0.0',
        },
      },
    ).create();
    await pubGet();
    final secondVersion = d.git('foo.git', [d.libPubspec('foo', '2.0.0')]);
    await secondVersion.commit();
    final newRef = await secondVersion.revParse('HEAD');

    final barSecondVersion = d.git('bar.git', [d.libPubspec('bar', '2.0.0')]);
    await barSecondVersion.commit();

    await _listReportApply(
      context,
      [
        _PackageVersion('foo', newRef),
      ],
      reportAssertions: (report) {
        expect(
          findChangeVersion(report, 'multiBreaking', 'foo'),
          newRef,
        );
      },
    );
  });

  testWithGolden('Finds smallest possible upgrade', (context) async {
    final server = await servePackages();
    server.serve('foo', '1.1.1'); // This version will be disallowed.

    await d.appDir(dependencies: {'foo': '^1.0.0'}).create();
    await pubGet();
    server.serve(
      'foo',
      '1.0.0',
    ); // We don't want the downgrade to go below the current.

    server.serve(
      'foo',
      '1.1.2',
    ); // This will also be disallowed, a minimal update should not find this.
    server.serve('foo', '1.1.3'); // We would like this to be the new version.
    server.serve('foo', '1.1.4'); // This version would not be a minimal update.

    await _reportWithForbidden(
      context,
      {
        'foo': ['1.1.1', '1.1.2'],
      },
      targetPackage: 'foo',
      resultAssertions: (r) {
        expect(findChangeVersion(r, 'smallestUpdate', 'foo'), '1.1.3');
      },
    );
  });

  testWithGolden('Smallest possible upgrade can upgrade beyond breaking',
      (context) async {
    final server = await servePackages();
    server.serve('foo', '1.1.1'); // This version will be disallowed.

    await d.appDir(dependencies: {'foo': '^1.0.0'}).create();
    await pubGet();

    server.serve(
      'foo',
      '2.0.0',
    ); // This will also be disallowed, a minimal update should not find this.
    server.serve('foo', '2.0.1'); // We would like this to be the new version.
    server.serve('foo', '2.0.2'); // This version would not be a minimal update.

    await _reportWithForbidden(
      context,
      {
        'foo': ['1.1.1', '2.0.0'],
      },
      targetPackage: 'foo',
      resultAssertions: (r) {
        expect(findChangeVersion(r, 'smallestUpdate', 'foo'), '2.0.1');
      },
    );
  });

  testWithGolden(
      'Smallest possible upgrade can upgrade other packages if needed',
      (context) async {
    final server = await servePackages();
    server.serve('bar', '1.0.0');
    server.serve('bar', '2.0.0');
    server.serve('bar', '2.2.0');

    server.serve(
      'foo',
      '1.1.1',
      deps: {'bar': '^1.0.0'},
    ); // This version will be disallowed.

    await d.appDir(dependencies: {'foo': '^1.0.0', 'bar': '^1.0.0'}).create();
    await pubGet();

    server.serve(
      'foo',
      '2.0.0',
      deps: {'bar': '^2.0.0'},
    ); // This will also be disallowed, a minimal update should not find this.
    server.serve(
      'foo',
      '2.0.1',
      deps: {'bar': '^2.0.0'},
    ); // We would like this to be the new version.
    server.serve(
      'foo',
      '2.0.2',
      deps: {'bar': '^2.0.0'},
    ); // This version would not be a minimal update.

    await _reportWithForbidden(
      context,
      {
        'foo': ['1.1.1', '2.0.0'],
        'bar': ['2.0.0'],
      },
      targetPackage: 'foo',
      resultAssertions: (r) {
        expect(findChangeVersion(r, 'smallestUpdate', 'foo'), '2.0.1');
        expect(findChangeVersion(r, 'smallestUpdate', 'bar'), '2.2.0');
      },
    );
  });

  testWithGolden('can upgrade workspaces', (context) async {
    (await servePackages())
      ..serve('foo', '1.2.3')
      ..serve('foo', '2.2.3', deps: {'transitive': '^1.0.0'})
      ..serve('bar', '1.2.3')
      ..serve('bar', '2.2.3')
      ..serve('only_a', '1.0.0')
      ..serve('only_a', '2.0.0')
      ..serve('dev', '1.0.0')
      ..serve('dev', '2.0.0')
      ..serve('transitive', '1.0.0')
      ..serveContentHashes = true;

    await dir(appPath, [
      libPubspec(
        'myapp',
        '1.2.3',
        extras: {
          'workspace': ['pkgs/a'],
        },
        deps: {
          'foo': '^1.0.0',
          'bar': '^1.0.0',
        },
        sdk: '^3.5.0',
      ),
      dir('pkgs', [
        dir('a', [
          libPubspec(
            'a',
            '1.1.1',
            deps: {'bar': '>=1.2.0 <1.5.0', 'only_a': '^1.0.0'},
            devDeps: {
              'foo': '^1.2.0',
              'dev': '^1.0.0',
            },
            resolutionWorkspace: true,
          ),
        ]),
      ]),
    ]).create();
    await pubGet(environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'});

    final result = await Process.run(
      Platform.resolvedExecutable,
      [snapshot, 'list'],
      environment: {
        ...getPubTestEnvironment(),
        '_PUB_TEST_SDK_VERSION': '3.5.0',
      },
      workingDirectory: p.join(d.sandbox, appPath, 'pkgs', 'a'),
    );

    expect(
      result.stderr,
      contains(
        'Only apply dependency_services to the root of the workspace.',
      ),
    );
    expect(result.exitCode, 1);

    await _listReportApply(
      context,
      [
        _PackageVersion('foo', '2.2.3'),
        _PackageVersion('transitive', '1.0.0'),
        _PackageVersion(
          'only_a',
          '2.0.0',
          constraint: VersionConstraint.parse('^2.0.0'),
        ),
      ],
      workspace: ['.', p.join('pkgs', 'a')],
      reportAssertions: (report) {
        expect(
          findChangeVersion(report, 'singleBreaking', 'foo'),
          '2.2.3',
        );
        expect(
          findChangeVersion(report, 'singleBreaking', 'transitive'),
          '1.0.0',
        );
      },
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
    );
  });
}

String? findChangeVersion(dynamic json, String updateType, String name) {
  return dig<String?>(
    json,
    ['dependencies', ('name', 'foo'), updateType, ('name', name), 'version'],
  );
}

class _PackageVersion {
  String name;
  String? version;
  VersionConstraint? constraint;
  _PackageVersion(this.name, this.version, {this.constraint});

  Map<String, Object?> toJson() => {
        'name': name,
        'version': version,
        if (constraint != null) 'constraint': constraint.toString(),
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
        'This test should not download archives! Requested ${request.url}',
      );
    });
  }
}
