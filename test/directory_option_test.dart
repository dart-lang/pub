// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart' as shelf;

import 'descriptor.dart';
import 'golden_file.dart';
import 'test_pub.dart';

Future<void> main() async {
  testWithGolden('commands taking a --directory/-C parameter work',
      (ctx) async {
    await servePackages()
      ..serve('foo', '1.0.0')
      ..serve('foo', '0.1.2')
      ..serve('bar', '1.2.3');
    await credentialsFile(globalServer, 'access-token').create();
    globalServer.handle(
      RegExp('/api/packages/test_pkg/uploaders'),
      (request) {
        return shelf.Response.ok(
          jsonEncode({
            'success': {'message': 'Good job!'}
          }),
          headers: {'content-type': 'application/json'},
        );
      },
    );

    await validPackage().create();
    await dir(appPath, [
      dir('bin', [
        file('app.dart', '''
main() => print('Hi');
''')
      ]),
      dir('example', [
        pubspec({
          'name': 'example',
          'dependencies': {
            'test_pkg': {'path': '../'}
          }
        })
      ]),
      dir('example2', [
        pubspec({
          'name': 'example',
          'dependencies': {
            'myapp': {'path': '../'} // Wrong name of dependency
          }
        })
      ]),
    ]).create();

    final cases = [
      // Try --directory after command.
      ['add', '--directory=$appPath', 'foo'],
      // Try the top-level version also.
      ['-C', appPath, 'add', 'bar'],
      // When both top-level and after command, the one after command takes
      // precedence.
      ['-C', p.join(appPath, 'example'), 'get', '--directory=$appPath', 'bar'],
      ['remove', 'bar', '-C', appPath],
      ['get', 'bar', '-C', appPath],
      ['get', 'bar', '-C', '$appPath/example'],
      ['get', 'bar', '-C', '$appPath/example2'],
      ['get', 'bar', '-C', '$appPath/broken_dir'],
      ['downgrade', '-C', appPath],
      ['upgrade', 'bar', '-C', appPath],
      ['run', '-C', appPath, 'bin/app.dart'],
      ['publish', '-C', appPath, '--dry-run'],
      ['uploader', '-C', appPath, 'add', 'sigurdm@google.com'],
      ['deps', '-C', appPath],
    ];

    for (var i = 0; i < cases.length; i++) {
      await ctx.run(
        cases[i],
        workingDirectory: sandbox,
      );
    }
  });
}
