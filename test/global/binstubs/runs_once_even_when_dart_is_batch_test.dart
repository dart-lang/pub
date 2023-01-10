// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test(
    'runs only once even when dart on path is a batch file (as in flutter/bin)',
    () async {
      final server = await servePackages();
      server.serve(
        'foo',
        '1.0.0',
        contents: [
          d.dir('bin', [d.file('script.dart', 'main(args) => print(args);')]),
        ],
        pubspec: {
          'executables': {'script': 'script'},
        },
      );

      await runPub(args: ['global', 'activate', 'foo']);

      await d.dir(
        'bin',
        [
          d.file('dart.bat', '''
@echo off
${Platform.resolvedExecutable} %*
'''),
        ],
      ).create();

      var process = await Process.run(
        p.join(d.sandbox, cachePath, 'bin', 'script.bat'),
        ['hi'],
        environment: {
          'PATH': [
            p.join(d.sandbox, 'bin'),
            p.dirname(Platform.resolvedExecutable)
          ].join(';'),
          ...getPubTestEnvironment(),
        },
      );
      expect((process.stdout as String).trim(), '[hi]');
      expect(process.exitCode, 0);
    },
    skip: !Platform.isWindows,
  );
}
