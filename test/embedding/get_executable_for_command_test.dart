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
    {allowSnapshot = true, result, errorMessage}) async {
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
    await d.dir('foo', [
      d.dir('bar', [d.file('bar.dart', 'main() {print(42);}')])
    ]).create();
    final dir = d.path('foo');

    await testGetExecutable('bar/bar.dart', dir,
        result: p.join('bar', 'bar.dart'));

    await testGetExecutable(p.join('bar', 'bar.dart'), dir,
        result: p.join('bar', 'bar.dart'));

    await testGetExecutable('${p.toUri(dir)}/bar/bar.dart', dir,
        result: p.join('bar', 'bar.dart'));
  });

  test('Looks for file when no pubspec.yaml', () async {
    await d.dir('foo', [
      d.dir('bar', [d.file('bar.dart', 'main() {print(42);}')])
    ]).create();
    final dir = d.path('foo');

    await testGetExecutable('bar/m.dart', dir,
        errorMessage: contains('Could not find file `bar/m.dart`'));
    await testGetExecutable(p.join('bar', 'm.dart'), dir,
        errorMessage: contains('Could not find file `bar${separator}m.dart`'));
  });

  test('Does `pub get` if there is a pubspec.yaml', () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependencies': {'foo': '^1.0.0'}
      }),
      d.dir('bin', [
        d.file('myapp.dart', 'main() {print(42);}'),
      ])
    ]).create();

    await serveNoPackages();
    // The solver uses word-wrapping in its error message, so we use \s to
    // accomodate.
    await testGetExecutable('bar/m.dart', d.path(appPath),
        errorMessage: matches(r'version\s+solving\s+failed'));
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

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '>=2.0.0 <3.0.0'},
        'dependencies': {
          'foo': {
            'hosted': {
              'name': 'foo',
              'url': getPubTestEnvironment()['PUB_HOSTED_URL'],
            },
            'version': '^1.0.0',
          },
        },
      }),
      d.dir('bin', [
        d.file('myapp.dart', 'main() {print(42);}'),
        d.file('tool.dart', 'main() {print(42);}')
      ])
    ]).create();
    final dir = d.path(appPath);

    await testGetExecutable('myapp', dir, result: 'bin${separator}myapp.dart');
    await testGetExecutable('myapp:myapp', dir,
        result: 'bin${separator}myapp.dart');
    await testGetExecutable(':myapp', dir, result: 'bin${separator}myapp.dart');
    await testGetExecutable(':tool', dir, result: 'bin${separator}tool.dart');
    await testGetExecutable('foo', dir,
        allowSnapshot: false,
        result: endsWith('foo-1.0.0${separator}bin${separator}foo.dart'));
    await testGetExecutable('foo', dir,
        result:
            '.dart_tool${separator}pub${separator}bin${separator}foo${separator}foo.dart-$_currentVersion.snapshot');
    await testGetExecutable('foo:tool', dir,
        allowSnapshot: false,
        result: endsWith('foo-1.0.0${separator}bin${separator}tool.dart'));
    await testGetExecutable('foo:tool', dir,
        result:
            '.dart_tool${separator}pub${separator}bin${separator}foo${separator}tool.dart-$_currentVersion.snapshot');
    await testGetExecutable(
      'unknown:tool',
      dir,
      errorMessage: 'Could not find package `unknown` or file `unknown:tool`',
    );
    await testGetExecutable(
      'foo:unknown',
      dir,
      errorMessage:
          'Could not find `bin${separator}unknown.dart` in package `foo`.',
    );
    await testGetExecutable(
      'unknownTool',
      dir,
      errorMessage:
          'Could not find package `unknownTool` or file `unknownTool`',
    );
  });
}

final _currentVersion = Platform.version.split(' ').first;
