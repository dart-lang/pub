// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test(
    'Complains if the current lockfile does not contain the expected package',
    () async {
      final server = await servePackages();
      server.serve(
        'foo',
        '1.0.0',
        contents: [
          d.dir('bin', [d.file('foo.dart', 'main() => print("hi"); ')]),
        ],
      );

      await runPub(args: ['global', 'activate', 'foo']);

      // Write a bad pubspec.lock file.
      final lockFilePath = p.join(
        d.sandbox,
        cachePath,
        'global_packages',
        'foo',
        'pubspec.lock',
      );
      File(lockFilePath).writeAsStringSync('''
packages: {}
sdks: {}
''');

      // Activating it again suggests deactivating the package.
      await runPub(
        args: ['global', 'activate', 'foo'],
        error: '''
Could not find `foo` in `$lockFilePath`.
Your Pub cache might be corrupted.

Consider `dart pub global deactivate foo`''',
        exitCode: 1,
      );

      await runPub(
        args: ['global', 'deactivate', 'foo'],
        output: 'Removed package `foo`',
      );
    },
  );
}
