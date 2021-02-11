// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'descriptor.dart';
import 'golden_file.dart';
import 'test_pub.dart';

Future<void> main() async {
  test('commands taking a --directory/-C parameter work', () async {
    await servePackages((b) =>
        b..serve('foo', '1.0.0')..serve('foo', '0.1.2')..serve('bar', '1.2.3'));
    await credentialsFile(globalPackageServer, 'access token').create();
    globalPackageServer
        .extraHandlers[RegExp('/api/packages/test_pkg/uploaders')] = (request) {
      return shelf.Response.ok(
          jsonEncode({
            'success': {'message': 'Good job!'}
          }),
          headers: {'content-type': 'application/json'});
    };

    await validPackage.create();
    await dir(appPath, [
      dir('bin', [
        file('app.dart', '''
main() => print('Hi');    
''')
      ]),
      dir('example', [
        pubspec({
          'name': 'example',
          'environment': {'sdk': '>=1.2.0 <2.0.0'},
          'dependencies': {
            'test_pkg': {'path': '../'}
          }
        })
      ]),
      dir('example2', [
        pubspec({
          'name': 'example',
          'environment': {'sdk': '>=1.2.0 <2.0.0'},
          'dependencies': {
            'myapp': {'path': '../'} // Wrong name of dependency
          }
        })
      ]),
    ]).create();
    final buffer = StringBuffer();
    Future<void> run(List<String> args) async {
      await runPubIntoBuffer(
        args,
        buffer,
        workingDirectory: sandbox,
        environment: {'_PUB_TEST_SDK_VERSION': '1.12.0'},
      );
    }

    await run(['add', '--directory=$appPath', 'foo']);
    // Try the top-level version also.
    await run(['-C', appPath, 'add', 'bar']);
    // When both top-level and after command, the one after command takes
    // precedence.
    await run([
      '-C',
      p.join(appPath, 'example'),
      'get',
      '--directory=$appPath',
      'bar',
    ]);
    await run(['remove', 'bar', '-C', appPath]);
    await run(['get', 'bar', '-C', appPath]);
    await run(['get', 'bar', '-C', '$appPath/example']);
    await run(['get', 'bar', '-C', '$appPath/example2']);
    await run(['get', 'bar', '-C', '$appPath/broken_dir']);
    await run(['downgrade', '-C', appPath]);
    await run(['upgrade', 'bar', '-C', appPath]);
    await run(['run', '-C', appPath, 'bin/app.dart']);
    await run(['publish', '-C', appPath, '--dry-run']);
    await run(['uploader', '-C', appPath, 'add', 'sigurdm@google.com']);
    await run(['deps', '-C', appPath]);
    // TODO(sigurdm): we should also test `list-package-dirs` - it is a bit
    // hard on windows due to quoted back-slashes on windows.
    expectMatchesGoldenFile(
        buffer.toString(), 'test/goldens/directory_option.txt');
  });
}
