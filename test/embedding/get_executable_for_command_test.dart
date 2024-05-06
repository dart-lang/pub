// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' show separator;
import 'package:path/path.dart' as p;
import 'package:pub/pub.dart';
import 'package:pub/src/log.dart' as log;

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

Future<void> testGetExecutable(
  String command,
  String root, {
  bool allowSnapshot = true,
  Object? executable,
  String? packageConfig,
  Object? errorMessage,
  CommandResolutionIssue? issue,
}) async {
  final cachePath = getPubTestEnvironment()['PUB_CACHE'];
  final oldVerbosity = log.verbosity;
  log.verbosity = log.Verbosity.none;
  if (executable == null) {
    expect(
      () => getExecutableForCommand(
        command,
        root: root,
        pubCacheDir: cachePath,
        allowSnapshot: allowSnapshot,
      ),
      throwsA(
        isA<CommandResolutionFailedException>()
            .having((e) => e.message, 'message', errorMessage)
            .having((e) => e.issue, 'issue', issue),
      ),
    );
  } else {
    final e = await getExecutableForCommand(
      command,
      root: root,
      pubCacheDir: cachePath,
      allowSnapshot: allowSnapshot,
    );
    expect(
      e,
      isA<DartExecutableWithPackageConfig>()
          .having((e) => e.executable, 'executable', executable)
          .having((e) => e.packageConfig, 'packageConfig', packageConfig),
    );
    expect(File(p.join(root, e.executable)).existsSync(), true);
    log.verbosity = oldVerbosity;
  }
}

Future<void> main() async {
  test('Finds a direct dart-file without pub get', () async {
    await d.dir('foo', [
      d.dir('bar', [d.file('bar.dart', 'main() {print(42);}')]),
    ]).create();
    final dir = d.path('foo');

    await testGetExecutable(
      'bar/bar.dart',
      dir,
      executable: p.join('bar', 'bar.dart'),
    );

    await testGetExecutable(
      p.join('bar', 'bar.dart'),
      dir,
      executable: p.join('bar', 'bar.dart'),
    );

    await testGetExecutable(
      '${p.toUri(dir)}/bar/bar.dart',
      dir,
      executable: p.join('bar', 'bar.dart'),
    );
  });

  test('Looks for file when no pubspec.yaml', () async {
    await d.dir('foo', [
      d.dir('bar', [d.file('bar.dart', 'main() {print(42);}')]),
    ]).create();
    final dir = d.path('foo');

    await testGetExecutable(
      'bar/m.dart',
      dir,
      errorMessage: contains('Could not find file `bar/m.dart`'),
      issue: CommandResolutionIssue.fileNotFound,
    );
    await testGetExecutable(
      p.join('bar', 'm.dart'),
      dir,
      errorMessage: contains('Could not find file `bar${separator}m.dart`'),
      issue: CommandResolutionIssue.fileNotFound,
    );
  });

  test('Error message when pubspec is broken', () async {
    await d.dir('foo', [
      d.pubspec({
        'name': 'broken name',
      }),
    ]).create();

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '^$_currentVersion'},
        'dependencies': {
          'foo': {
            'path': '../foo',
          },
        },
      }),
    ]).create();
    final dir = d.path(appPath);
    await testGetExecutable(
      'foo:app',
      dir,
      errorMessage: allOf(
        contains(
          'Error on line 1, column 9 of ${d.sandbox}${p.separator}foo${p.separator}pubspec.yaml: "name" field must be a valid Dart identifier.',
        ),
        contains(
          '{"name":"broken name","environment":{"sdk":"$defaultSdkConstraint"}}',
        ),
      ),
      issue: CommandResolutionIssue.pubGetFailed,
    );
  });

  test('Reports file not found if the path looks like a file', () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '^$_currentVersion'},
        'dependencies': {'foo': '^1.0.0'},
      }),
      d.dir('bin', [
        d.file('myapp.dart', 'main() {print(42);}'),
      ]),
    ]).create();

    await servePackages();
    // The solver uses word-wrapping in its error message, so we use \s to
    // accommodate.
    await testGetExecutable(
      'bar/m.dart',
      d.path(appPath),
      errorMessage: matches(r'Could not find file `bar/m.dart`'),
      issue: CommandResolutionIssue.fileNotFound,
    );
  });

  test('Reports parse failure', () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '^$_currentVersion'},
      }),
    ]).create();
    await testGetExecutable(
      '::',
      d.path(appPath),
      errorMessage: contains(r'cannot contain multiple ":"'),
      issue: CommandResolutionIssue.parseError,
    );
  });

  test('Reports compilation failure', () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '^$_currentVersion'},
      }),
      d.dir('bin', [
        d.file('foo.dart', 'main() {'),
      ]),
    ]).create();

    await servePackages();
    // The solver uses word-wrapping in its error message, so we use \s to
    // accommodate.
    await testGetExecutable(
      ':foo',
      d.path(appPath),
      errorMessage: matches(r'foo.dart:1:8:'),
      issue: CommandResolutionIssue.compilationFailed,
    );
  });

  test('Finds files', () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      pubspec: {
        'environment': {'sdk': '^$_currentVersion'},
      },
      deps: {
        'transitive': {'hosted': globalServer.url},
      },
      contents: [
        d.dir('bin', [
          d.file('foo.dart', 'main() {print(42);}'),
          d.file('tool.dart', 'main() {print(42);}'),
        ]),
      ],
    );

    server.serve(
      'transitive',
      '1.0.0',
      pubspec: {
        'environment': {'sdk': '^$_currentVersion'},
      },
      contents: [
        d.dir('bin', [d.file('transitive.dart', 'main() {print(42);}')]),
      ],
    );

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '^$_currentVersion'},
        'dependencies': {
          'foo': {
            'hosted': globalServer.url,
            'version': '^1.0.0',
          },
        },
      }),
      d.dir('bin', [
        d.file('myapp.dart', 'main() {print(42);}'),
        d.file('tool.dart', 'main() {print(42);}'),
      ]),
    ]).create();
    final dir = d.path(appPath);

    await testGetExecutable(
      'myapp',
      dir,
      executable: p.join(
        '.dart_tool',
        'pub',
        'bin',
        'myapp',
        'myapp.dart-$_currentVersion.snapshot',
      ),
      packageConfig: p.join('.dart_tool', 'package_config.json'),
    );
    await testGetExecutable(
      'myapp:myapp',
      dir,
      executable: p.join(
        '.dart_tool',
        'pub',
        'bin',
        'myapp',
        'myapp.dart-$_currentVersion.snapshot',
      ),
      packageConfig: p.join('.dart_tool', 'package_config.json'),
    );
    await testGetExecutable(
      ':myapp',
      dir,
      executable: p.join(
        '.dart_tool',
        'pub',
        'bin',
        'myapp',
        'myapp.dart-$_currentVersion.snapshot',
      ),
      packageConfig: p.join('.dart_tool', 'package_config.json'),
    );
    await testGetExecutable(
      ':tool',
      dir,
      executable: p.join(
        '.dart_tool',
        'pub',
        'bin',
        'myapp',
        'tool.dart-$_currentVersion.snapshot',
      ),
      packageConfig: p.join('.dart_tool', 'package_config.json'),
    );
    await testGetExecutable(
      'foo',
      dir,
      allowSnapshot: false,
      executable: endsWith('foo-1.0.0${separator}bin${separator}foo.dart'),
      packageConfig: p.join('.dart_tool', 'package_config.json'),
    );
    await testGetExecutable(
      'foo',
      dir,
      executable:
          '.dart_tool${separator}pub${separator}bin${separator}foo${separator}foo.dart-$_currentVersion.snapshot',
      packageConfig: p.join('.dart_tool', 'package_config.json'),
    );
    await testGetExecutable(
      'foo:tool',
      dir,
      allowSnapshot: false,
      executable: endsWith('foo-1.0.0${separator}bin${separator}tool.dart'),
      packageConfig: p.join('.dart_tool', 'package_config.json'),
    );
    await testGetExecutable(
      'foo:tool',
      dir,
      executable:
          '.dart_tool${separator}pub${separator}bin${separator}foo${separator}tool.dart-$_currentVersion.snapshot',
      packageConfig: p.join('.dart_tool', 'package_config.json'),
    );
    await testGetExecutable(
      'unknown:tool',
      dir,
      errorMessage: 'Could not find package `unknown` or file `unknown:tool`',
      issue: CommandResolutionIssue.packageNotFound,
    );
    await testGetExecutable(
      'foo:unknown',
      dir,
      errorMessage:
          'Could not find `bin${separator}unknown.dart` in package `foo`.',
      issue: CommandResolutionIssue.noBinaryFound,
    );
    await testGetExecutable(
      'unknownTool',
      dir,
      errorMessage:
          'Could not find package `unknownTool` or file `unknownTool`',
      issue: CommandResolutionIssue.packageNotFound,
    );
    await testGetExecutable(
      'transitive',
      dir,
      executable: p.relative(
        p.join(
          d.sandbox,
          d.hostedCachePath(port: globalServer.port),
          'transitive-1.0.0',
          'bin',
          'transitive.dart',
        ),
        from: dir,
      ),
      allowSnapshot: false,
      packageConfig: p.join('.dart_tool', 'package_config.json'),
    );
  });

  test('works with workspace', () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      contents: [
        d.dir('bin', [
          d.file('foo.dart', 'main() {print(42);}'),
          d.file('tool.dart', 'main() {print(42);}'),
        ]),
      ],
    );

    await d.dir(appPath, [
      d.libPubspec(
        'myapp',
        '1.2.3',
        deps: {
          'a': 'any',
        },
        extras: {
          'workspace': ['pkgs/a', 'pkgs/b'],
        },
        sdk: '^3.5.0-0',
      ),
      d.dir('bin', [
        d.file('myapp.dart', 'main() {print(42);}'),
        d.file('tool.dart', 'main() {print(42);}'),
      ]),
      d.dir('pkgs', [
        d.dir('a', [
          d.libPubspec(
            'a',
            '1.0.0',
            resolutionWorkspace: true,
          ),
          d.dir('bin', [
            d.file('a.dart', 'main() {print(42);}'),
            d.file('tool.dart', 'main() {print(42);}'),
          ]),
        ]),
        d.dir('b', [
          d.libPubspec(
            'b',
            '1.0.0',
            resolutionWorkspace: true,
          ),
          d.dir('bin', [
            d.file('b.dart', 'main() {print(42);}'),
            d.file('tool.dart', 'main() {print(42);}'),
          ]),
        ]),
      ]),
    ]).create();
    await pubGet(
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
    );

    await testGetExecutable(
      'myapp',
      p.join(d.sandbox, appPath, 'pkgs', 'a'),
      executable: p.join(
        '..',
        '..',
        '.dart_tool',
        'pub',
        'bin',
        'myapp',
        'myapp.dart-$_currentVersion.snapshot',
      ),
      packageConfig: p.join('..', '..', '.dart_tool', 'package_config.json'),
    );
    await testGetExecutable(
      'a',
      p.join(d.sandbox, appPath, 'pkgs'),
      executable: p.join(
        'a',
        'bin',
        'a.dart',
      ),
      allowSnapshot: false,
      packageConfig: p.join('..', '.dart_tool', 'package_config.json'),
    );
    await testGetExecutable(
      'b:tool',
      p.join(d.sandbox, appPath),
      allowSnapshot: false,
      executable: p.join(
        'pkgs',
        'b',
        'bin',
        'tool.dart',
      ),
      packageConfig: p.join('.dart_tool', 'package_config.json'),
    );
  });
}

final _currentVersion = Platform.version.split(' ').first;
