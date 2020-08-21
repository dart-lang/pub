// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:test/test.dart';
import 'package:pub/pub.dart';
import 'package:path/path.dart' show separator;
import 'package:path/path.dart' as p;

import '../descriptor.dart' as d;
import '../test_pub.dart';

Future<void> testGetExecutable(String command, String root,
    {allowSnapshot: true, result, errorMessage}) async {
  final _cachePath = getPubTestEnvironment()['PUB_CACHE'];
  if (result == null) {
    expect(
      () => getExecutableForCommand(
        command,
        root: root,
        pubCacheDir: _cachePath,
        allowSnapshot: allowSnapshot,
      ),
      throwsA(
        isA<CommandResolutionFailedException>()
            .having((e) => e.message, 'message', errorMessage),
      ),
    );
  } else {
    final path = await getExecutableForCommand(
      command,
      root: root,
      pubCacheDir: _cachePath,
      allowSnapshot: allowSnapshot,
    );
    expect(path, result);
    expect(File(p.join(root, path)).existsSync(), true);
  }
}

Future<void> main() async {
  test('Finds a direct dart-file without pub get', () async {
    final dir = d.dir('foo', [
      d.dir('bar', [d.file('bar.dart', 'main() {print(42);}')])
    ]);
    await dir.create();
    await testGetExecutable('bar/bar.dart', dir.io.path,
        result: 'bar/bar.dart');

    await testGetExecutable('${p.toUri(dir.io.path)}/bar/bar.dart', dir.io.path,
        result: 'bar/bar.dart');
  });

  test('Looks for file when no pubspec.yaml', () async {
    final dir = d.dir('foo', [
      d.dir('bar', [d.file('bar.dart', 'main() {print(42);}')])
    ]);
    await dir.create();
    await testGetExecutable('bar/m.dart', dir.io.path,
        errorMessage: contains('Could not find file `bar${separator}m.dart`'));
  });

  test('Does `pub get` if there is a pubspec.yaml', () async {
    final dir = d.dir('myapp', [
      d.pubspec({
        'name': 'myapp',
        'dependencies': {'foo': '^1.0.0'}
      }),
      d.dir('bin', [
        d.file('myapp.dart', 'main() {print(42);}'),
      ])
    ]);
    await dir.create();

    await serveNoPackages();
    // The solver uses word-wrapping in its error message, so we use \s to
    // accomodate.
    await testGetExecutable('bar/m.dart', dir.io.path,
        errorMessage: matches('version\ssolving\sfailed'));
  });

  test('Finds files', () async {
    await servePackages((b) => b
      ..serve('foo', '1.0.0', pubspec: {
        'environment': {'sdk': '>=$_currentVersion <3.0.0'}
      }, contents: [
        d.dir('bin', [
          d.file('foo.dart', 'main() {print(42);}'),
          d.file('tool.dart', 'main() {print(42);}')
        ])
      ]));

    final dir = d.dir(appPath, [
      d.appPubspec({
        'foo': {
          'hosted': {
            'name': 'foo',
            'url': getPubTestEnvironment()['PUB_HOSTED_URL']
          },
          'version': '^1.0.0'
        }
      }),
      d.dir('bin', [
        d.file('myapp.dart', 'main() {print(42);}'),
        d.file('tool.dart', 'main() {print(42);}')
      ])
    ]);
    await dir.create();

    await testGetExecutable('myapp', dir.io.path, result: 'bin/myapp.dart');
    await testGetExecutable('myapp:myapp', dir.io.path,
        result: 'bin/myapp.dart');
    await testGetExecutable(':myapp', dir.io.path, result: 'bin/myapp.dart');
    await testGetExecutable(':tool', dir.io.path, result: 'bin/tool.dart');
    await testGetExecutable('foo', dir.io.path,
        allowSnapshot: false, result: endsWith('foo-1.0.0/bin/foo.dart'));
    await testGetExecutable('foo', dir.io.path,
        result: '.dart_tool/pub/bin/foo/foo.dart-$_currentVersion.snapshot');
    await testGetExecutable('foo:tool', dir.io.path,
        allowSnapshot: false, result: endsWith('foo-1.0.0/bin/tool.dart'));
    await testGetExecutable('foo:tool', dir.io.path,
        result: '.dart_tool/pub/bin/foo/tool.dart-$_currentVersion.snapshot');
    await testGetExecutable(
      'unknown:tool',
      dir.io.path,
      errorMessage: 'Could not find package `unknown` or file `unknown:tool`',
    );
    await testGetExecutable(
      'foo:unknown',
      dir.io.path,
      errorMessage: 'Could not find `bin/unknown.dart` in package `foo`.',
    );
    await testGetExecutable(
      'unknownTool',
      dir.io.path,
      errorMessage:
          'Could not find package `unknownTool` or file `unknownTool`',
    );
  });
}

final _currentVersion = Platform.version.split(' ').first;
