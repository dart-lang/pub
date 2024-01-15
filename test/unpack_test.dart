// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub/src/exit_codes.dart';
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
      args: ['unpack', 'foo:1:2:3'],
      error: contains(
        'Use a single `:` to divide between package name and version.',
      ),
      exitCode: USAGE,
    );

    await runPub(
      args: ['unpack', 'foo:1.0'],
      error: 'Bad version string: Could not parse "1.0".',
      exitCode: 1,
    );

    await runPub(
      args: ['unpack', 'foo'],
    );
    await runPub(
      args: ['unpack', 'foo'],
      error: 'Target directory `.${s}foo-1.2.3` already exists.',
      exitCode: 1,
    );
  });

  test('Chooses right version to unpack', () async {
    await d.dir(appPath).create();
    final server = await servePackages();
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
Resolving dependencies in .${s}foo-1.2.3...
'''),
        contains('To explore type: cd .${s}foo-1.2.3'),
        contains(
          'To explore the example type: cd .${s}foo-1.2.3${s}example',
        ),
      ),
    );

    expect(
      File(p.join(d.sandbox, appPath, 'foo-1.2.3', 'pubspec.yaml'))
          .existsSync(),
      isTrue,
    );
    expect(
      File(p.join(d.sandbox, appPath, 'foo-1.2.3', 'example', 'pubspec.yaml'))
          .existsSync(),
      isTrue,
    );

    await runPub(
      args: ['unpack', 'foo:1.2.3-pre', '--destination=../'],
      output: allOf(
        contains('''
Downloading foo 1.2.3-pre to `..${s}foo-1.2.3-pre`...
Resolving dependencies in ..${s}foo-1.2.3-pre...
'''),
        contains('To explore type: cd ..${s}foo-1.2.3-pre'),
      ),
    );

    expect(
      File(p.join(d.sandbox, 'foo-1.2.3-pre', 'pubspec.yaml')).existsSync(),
      isTrue,
    );
  });

  test('unpack from third party package repository', () async {
    await d.dir(appPath).create();
    final server = await startPackageServer();
    server.serve('foo', '1.2.3');
    await runPub(args: ['unpack', 'foo', '--repository=${server.url}']);
  });
}
