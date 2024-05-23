// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub/pub.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'embedding_test.dart';

enum ResolutionAttempt {
  resolution,
  fastPath,
  noResolution,
}

Future<void> testGetExecutable(
  String command,
  String root, {
  bool allowSnapshot = true,
  String? executable,
  String? packageConfig,
  Object? errorMessage,
  required ResolutionAttempt resolution,
  CommandResolutionIssue? issue,
  Map<String, String>? environment,
}) async {
  final buffer = StringBuffer();
  await runEmbeddingToBuffer(
    [
      'pub',
      '--verbose',
      'get-executable-for-command',
      command,
      if (allowSnapshot) '--allow-snapshot' else '--no-allow-snapshot',
    ],
    buffer,
    workingDirectory: root,
    exitCode: errorMessage == null ? 0 : isNot(0),
    environment: environment,
  );
  final output = buffer.toString();
  if (errorMessage != null) {
    expect(output, errorMessage);
    expect(output, contains('Issue: $issue'));
  } else {
    expect(output, contains(filterUnstableText('Executable: $executable\n')));
    expect(
      File(p.join(root, executable)).existsSync(),
      true,
      reason: '${p.join(root, executable)} should exist',
    );
    expect(
      output,
      contains(
        'Package config: ${filterUnstableText(packageConfig ?? 'No package config')}\n',
      ),
    );
  }
  switch (resolution) {
    case ResolutionAttempt.fastPath:
      expect(output, contains('[E] FINE: Package Config up to date.'));
    case ResolutionAttempt.noResolution:
      expect(output, isNot(contains('[E] FINE: Package Config up to date.')));
      expect(output, isNot(contains('MSG : Resolving dependencies')));
    case ResolutionAttempt.resolution:
      expect(output, contains('MSG : Resolving dependencies'));
  }
}

void testGetExecutableForCommand() {
  group('getExecutableForCommand', () {
    test('Finds a direct dart-file without pub get', () async {
      await servePackages();
      await d.dir('foo', [
        d.dir('bar', [d.file('bar.dart', 'main() {print(42);}')]),
      ]).create();
      final dir = d.path('foo');

      await testGetExecutable(
        'bar/bar.dart',
        dir,
        executable: p.join('bar', 'bar.dart'),
        resolution: ResolutionAttempt.noResolution,
      );

      await testGetExecutable(
        p.join('bar', 'bar.dart'),
        dir,
        executable: p.join('bar', 'bar.dart'),
        resolution: ResolutionAttempt.noResolution,
      );

      await testGetExecutable(
        '${p.toUri(dir)}/bar/bar.dart',
        dir,
        executable: p.join('bar', 'bar.dart'),
        resolution: ResolutionAttempt.noResolution,
      );
    });

    test('Looks for file when no pubspec.yaml', () async {
      await servePackages();
      await d.dir('foo', [
        d.dir('bar', [d.file('bar.dart', 'main() {print(42);}')]),
      ]).create();
      final dir = d.path('foo');

      await testGetExecutable(
        'bar/m.dart',
        dir,
        errorMessage: contains('Could not find file `bar/m.dart`'),
        issue: CommandResolutionIssue.fileNotFound,
        resolution: ResolutionAttempt.noResolution,
      );
      await testGetExecutable(
        p.join('bar', 'm.dart'),
        dir,
        errorMessage: contains('Could not find file `bar/m.dart`'),
        issue: CommandResolutionIssue.fileNotFound,
        resolution: ResolutionAttempt.noResolution,
      );
    });

    test('Error message when pubspec is broken', () async {
      await servePackages();
      await d.dir('foo', [
        d.pubspec({
          'name': 'broken name',
        }),
      ]).create();

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
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
            'Error on line 1, column 9 of ../foo/pubspec.yaml: "name" field must be a valid Dart identifier.',
          ),
          contains(
            '{"name":"broken name","environment":{"sdk":"$defaultSdkConstraint"}}',
          ),
        ),
        issue: CommandResolutionIssue.pubGetFailed,
        resolution: ResolutionAttempt.resolution,
      );
    });

    test('Reports file not found if the path looks like a file', () async {
      await servePackages();
      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
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
        resolution: ResolutionAttempt.noResolution,
      );
    });

    test('Reports parse failure', () async {
      await servePackages();
      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
        }),
      ]).create();
      await testGetExecutable(
        '::',
        d.path(appPath),
        errorMessage: contains(r'cannot contain multiple ":"'),
        issue: CommandResolutionIssue.parseError,
        resolution: ResolutionAttempt.resolution,
      );
    });

    test('Reports compilation failure', () async {
      await servePackages();
      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
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
        resolution: ResolutionAttempt.resolution,
      );
    });

    test('Finds files', () async {
      final server = await servePackages();
      server.serve(
        'foo',
        '1.0.0',
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
        contents: [
          d.dir('bin', [d.file('transitive.dart', 'main() {print(42);}')]),
        ],
      );

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
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
          'myapp.dart-3.1.2+3.snapshot',
        ),
        packageConfig: p.join('.dart_tool', 'package_config.json'),
        resolution: ResolutionAttempt.resolution,
      );
      await testGetExecutable(
        'myapp:myapp',
        dir,
        executable: p.join(
          '.dart_tool',
          'pub',
          'bin',
          'myapp',
          'myapp.dart-3.1.2+3.snapshot',
        ),
        packageConfig: p.join('.dart_tool', 'package_config.json'),
        resolution: ResolutionAttempt.fastPath,
      );
      await testGetExecutable(
        ':myapp',
        dir,
        executable: p.join(
          '.dart_tool',
          'pub',
          'bin',
          'myapp',
          'myapp.dart-3.1.2+3.snapshot',
        ),
        packageConfig: p.join('.dart_tool', 'package_config.json'),
        resolution: ResolutionAttempt.fastPath,
      );
      await testGetExecutable(
        ':tool',
        dir,
        executable: p.join(
          '.dart_tool',
          'pub',
          'bin',
          'myapp',
          'tool.dart-3.1.2+3.snapshot',
        ),
        packageConfig: p.join('.dart_tool', 'package_config.json'),
        resolution: ResolutionAttempt.fastPath,
      );
      await testGetExecutable(
        'foo',
        dir,
        allowSnapshot: false,
        executable: p.join(
          d.sandbox,
          d.hostedCachePath(),
          'foo-1.0.0',
          'bin',
          'foo.dart',
        ),
        packageConfig: p.join('.dart_tool', 'package_config.json'),
        resolution: ResolutionAttempt.fastPath,
      );
      await testGetExecutable(
        'foo',
        dir,
        executable: p.join(
          '.dart_tool',
          'pub',
          'bin',
          'foo',
          'foo.dart-3.1.2+3.snapshot',
        ),
        packageConfig: p.join('.dart_tool', 'package_config.json'),
        resolution: ResolutionAttempt.fastPath,
      );
      await testGetExecutable(
        'foo:tool',
        dir,
        allowSnapshot: false,
        executable: p.join(
          d.sandbox,
          d.hostedCachePath(),
          'foo-1.0.0',
          'bin',
          'tool.dart',
        ),
        packageConfig: p.join('.dart_tool', 'package_config.json'),
        resolution: ResolutionAttempt.fastPath,
      );
      await testGetExecutable(
        'foo:tool',
        dir,
        executable: p.join(
          '.dart_tool',
          'pub',
          'bin',
          'foo',
          'tool.dart-3.1.2+3.snapshot',
        ),
        packageConfig: p.join('.dart_tool', 'package_config.json'),
        resolution: ResolutionAttempt.fastPath,
      );
      await testGetExecutable(
        'unknown:tool',
        dir,
        errorMessage: contains(
          'Could not find package `unknown` or file `unknown:tool`',
        ),
        issue: CommandResolutionIssue.packageNotFound,
        resolution: ResolutionAttempt.fastPath,
      );
      await testGetExecutable(
        'foo:unknown',
        dir,
        errorMessage: contains(
          'Could not find `bin/unknown.dart` in package `foo`.',
        ),
        issue: CommandResolutionIssue.noBinaryFound,
        resolution: ResolutionAttempt.fastPath,
      );
      await testGetExecutable(
        'unknownTool',
        dir,
        errorMessage: contains(
          'Could not find package `unknownTool` or file `unknownTool`',
        ),
        issue: CommandResolutionIssue.packageNotFound,
        resolution: ResolutionAttempt.fastPath,
      );
      await testGetExecutable(
        'transitive',
        dir,
        executable: p.join(
          d.sandbox,
          d.hostedCachePath(port: globalServer.port),
          'transitive-1.0.0',
          'bin',
          'transitive.dart',
        ),
        allowSnapshot: false,
        packageConfig: p.join('.dart_tool', 'package_config.json'),
        resolution: ResolutionAttempt.fastPath,
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
            'foo': {
              'hosted': globalServer.url,
              'version': '^1.0.0',
            },
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
              extras: {
                'workspace': ['sub'],
              },
            ),
            d.dir('bin', [
              d.file('a.dart', 'main() {print(42);}'),
              d.file('tool.dart', 'main() {print(42);}'),
            ]),
            d.dir('sub', [
              d.libPubspec(
                'sub',
                '1.0.0',
                resolutionWorkspace: true,
              ),
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
          'myapp.dart-3.5.0.snapshot',
        ),
        environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
        packageConfig: p.join('..', '..', '.dart_tool', 'package_config.json'),
        resolution: ResolutionAttempt.fastPath,
      );
      await testGetExecutable(
        'myapp',
        p.join(d.sandbox, appPath, 'pkgs', 'a', 'sub'),
        executable: p.join(
          '..',
          '..',
          '..',
          '.dart_tool',
          'pub',
          'bin',
          'myapp',
          'myapp.dart-3.5.0.snapshot',
        ),
        environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
        packageConfig:
            p.join('..', '..', '..', '.dart_tool', 'package_config.json'),
        resolution: ResolutionAttempt.fastPath,
      );

      await testGetExecutable(
        'a',
        p.join(d.sandbox, appPath, 'pkgs'),
        executable: p.join(
          d.sandbox,
          appPath,
          'pkgs',
          'a',
          'bin',
          'a.dart',
        ),
        allowSnapshot: false,
        packageConfig: p.join('..', '.dart_tool', 'package_config.json'),
        environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
        resolution: ResolutionAttempt.fastPath,
      );
      await testGetExecutable(
        'b:tool',
        p.join(d.sandbox, appPath),
        allowSnapshot: false,
        executable: p.join(
          d.sandbox,
          appPath,
          'pkgs',
          'b',
          'bin',
          'tool.dart',
        ),
        packageConfig: p.join('.dart_tool', 'package_config.json'),
        environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
        resolution: ResolutionAttempt.fastPath,
      );
      await testGetExecutable(
        'foo',
        p.join(d.sandbox, appPath),
        allowSnapshot: false,
        executable: p.join(
          d.sandbox,
          d.hostedCachePath(),
          'foo-1.0.0',
          'bin',
          'foo.dart',
        ),
        packageConfig: p.join('.dart_tool', 'package_config.json'),
        environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
        resolution: ResolutionAttempt.fastPath,
      );
      await testGetExecutable(
        ':tool',
        p.join(d.sandbox, appPath, 'pkgs', 'a'),
        allowSnapshot: false,
        executable: p.join(
          d.sandbox,
          appPath,
          'pkgs',
          'a',
          'bin',
          'tool.dart',
        ),
        packageConfig: p.join('..', '..', '.dart_tool', 'package_config.json'),
        environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
        resolution: ResolutionAttempt.fastPath,
      );
    });
  });
}
