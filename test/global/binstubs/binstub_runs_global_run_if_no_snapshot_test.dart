// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:pub/src/path.dart';
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('the binstubs runs pub global run if there is no snapshot', () async {
    await d.dir('foo', [
      d.pubspec({
        'name': 'foo',
        'executables': {'foo-script': 'script'},
      }),
      d.dir('bin', [d.file('script.dart', "main() => print('ok');")]),
    ]).create();

    // Path packages are mutable, so no snapshot is created.
    await runPub(
      args: ['global', 'activate', '--source', 'path', '../foo'],
      output: contains('Installed executable foo-script.'),
    );

    await d.dir(cachePath, [
      d.dir('bin', [
        d.file(binStubName('foo-script'), contains('global run foo:script')),
      ]),
    ]).validate();
  });

  test('the binstubs of hosted package runs pub global run '
      'if there is no snapshot', () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      contents: [
        d.dir('bin', [d.file('script.dart', "main() => print('ok');")]),
      ],
      pubspec: {
        'name': 'foo',
        'executables': {'foo-script': 'script'},
      },
    );

    await runPub(
      args: ['global', 'activate', 'foo'],
      output: contains('Installed executable foo-script.'),
    );

    await d.dir(cachePath, [
      d.dir('bin', [
        d.file(binStubName('foo-script'), contains('global run foo:script')),
      ]),
    ]).validate();

    // Force refresh of snapshot/binstub
    Directory(
      p.join(d.sandbox, cachePath, 'global_packages', 'foo', 'bin'),
    ).deleteSync(recursive: true);
    final binstub = p.join(
      d.sandbox,
      cachePath,
      'bin',
      'foo-script${Platform.isWindows ? '.bat' : ''}',
    );
    final result = await Process.run(
      binstub,
      [],
      environment: getPubTestEnvironment(),
    );
    expect(result.stderr, '');
    expect(result.exitCode, 0);
    expect(result.stdout, contains('ok'));

    await d.dir(cachePath, [
      d.dir('bin', [
        d.file(binStubName('foo-script'), contains('global run foo:script')),
      ]),
    ]).validate();
  });
}
