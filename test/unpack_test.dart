// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:io';

import 'package:pub/src/exit_codes.dart';
import 'package:pub/src/path.dart';
import 'package:test/test.dart';

import 'descriptor.dart' as d;
import 'test_pub.dart';

final s = Platform.pathSeparator;

void main() {
  test('handles errors', () async {
    await d.dir(appPath).create();
    final server = await servePackages();
    server.serve('foo', '1.2.3');
    await runPub(
      args: ['unpack', 'foo@1:2:3'],
      error: contains(
        'Error on line 1, column 1 of descriptor: Invalid version constraint: '
        'Could not parse version "1:2:3". Unknown text at "1:2:3".',
      ),
      exitCode: DATA,
    );

    await runPub(
      args: ['unpack', 'foo@1.0'],
      error:
          'Error on line 1, column 1 of descriptor: '
          'A dependency specification must be a string or a mapping.',
      exitCode: DATA,
    );

    await runPub(args: ['unpack', 'foo']);
    await runPub(
      args: ['unpack', 'foo'],
      error:
          'Target directory `.${s}foo-1.2.3` already exists. '
          'Use --force to overwrite.',
      exitCode: 1,
    );
    await runPub(args: ['unpack', 'foo', '--force']);
  });

  test('Chooses right version to unpack', () async {
    await d.dir(appPath).create();
    final server = await servePackages();
    server.serve('foo', '0.1.1');
    server.serve('foo', '0.1.0');
    server.serve(
      'foo',
      '1.2.3',
      contents: [
        d.dir('example', [
          d.pubspec({
            'name': 'example',
            'dependencies': {
              'foo': {'path': '..'},
            },
          }),
        ]),
      ],
    );
    server.serve('foo', '1.2.3-pre');
    await d.appDir().create();

    await runPub(
      args: ['unpack', 'foo'],
      output: allOf(
        contains('''
Downloading foo 1.2.3 to `.${s}foo-1.2.3`...
Resolving dependencies in `.${s}foo-1.2.3`...
'''),
        contains('To explore type: cd .${s}foo-1.2.3'),
        contains('To explore the example type: cd .${s}foo-1.2.3${s}example'),
      ),
    );

    expect(
      File(
        p.join(d.sandbox, appPath, 'foo-1.2.3', 'pubspec.yaml'),
      ).existsSync(),
      isTrue,
    );
    expect(
      File(
        p.join(d.sandbox, appPath, 'foo-1.2.3', 'example', 'pubspec.yaml'),
      ).existsSync(),
      isTrue,
    );

    await runPub(
      args: ['unpack', 'foo@1.2.3-pre', '--output=../'],
      output: allOf(
        contains('''
Downloading foo 1.2.3-pre to `../foo-1.2.3-pre`...
Resolving dependencies in `../foo-1.2.3-pre`...
'''),
        contains('To explore type: cd ../foo-1.2.3-pre'),
      ),
    );

    expect(
      File(p.join(d.sandbox, 'foo-1.2.3-pre', 'pubspec.yaml')).existsSync(),
      isTrue,
    );

    await runPub(
      args: ['unpack', 'foo@^0.1.0'],
      output: contains('Downloading foo 0.1.1 to `.${s}foo-0.1.1`...'),
    );
  });

  test('unpack from third party package repository', () async {
    await d.dir(appPath).create();
    final server = await startPackageServer();
    server.serve('foo', '1.0.0');
    server.serve('foo', '1.2.3');
    await runPub(
      args: ['unpack', 'foo@{"hosted":"${server.url}", "version":"1.0.0"}'],
      output: contains('Downloading foo 1.0.0 to `.${s}foo-1.0.0`...'),
    );
  });

  test('unpacks and resolve workspace project', () async {
    await d.dir(appPath).create();

    final server = await servePackages();
    server.serve('bar', '1.0.0');
    server.serve(
      'foo',
      '1.0.0',
      pubspec: {
        'environment': {'sdk': '^3.5.0'},
        'resolution': 'workspace',
        'workspace': ['example'],
      },
      contents: [
        d.dir('example', [
          d.libPubspec(
            'example',
            '1.0.0',
            sdk: '^3.5.0',
            deps: {'foo': null, 'bar': '^1.0.0'},
            extras: {'resolution': 'workspace'},
          ),
        ]),
      ],
    );
    await runPub(
      args: ['unpack', 'foo@1.0.0'],
      output: allOf(
        contains('Downloading foo 1.0.0 to `.${s}foo-1.0.0`...'),
        contains('+ bar'),
      ),
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
    );
    await d.dir(appPath, [
      d.dir('foo-1.0.0', [d.file('pubspec_overrides.yaml', 'resolution:\n')]),
    ]).validate();
  });

  test('still supports : as separator', () async {
    await d.dir(appPath).create();
    final server = await servePackages();
    server.serve('foo', '1.2.3');
    await runPub(
      args: ['unpack', 'foo:1.2.3'],
      output: contains('Downloading foo 1.2.3 to `.${s}foo-1.2.3`...'),
    );
  });
}
