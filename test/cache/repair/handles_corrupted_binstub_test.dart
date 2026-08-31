// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:io';

import 'package:pub/src/path.dart';
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

const _foreignBinStub = '''
#!/usr/bin/env sh
# Package: foo
# Executable: script
# Script: script
echo not-pub
''';

const _malformedPubBinStub = '''
# This file was created by pub v0.1.2-3.
# Package: ../foo
# Version: 1.0.0
# Executable: script
# Script: script
''';

void main() {
  test('preserves a foreign binstub and continues repairing', () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      contents: [
        d.dir('bin', [d.file('script.dart', "main(args) => print('ok');")]),
      ],
    );

    await runPub(args: ['global', 'activate', 'foo']);

    await d.dir(cachePath, [
      d.dir('bin', [d.file(binStubName('script'), _foreignBinStub)]),
    ]).create();

    await runPub(
      args: ['cache', 'repair', '--all'],
      output: contains('Reactivated 1 package.'),
      error: contains('Error reading binstub for "script":'),
    );

    await d.dir(cachePath, [
      d.dir('bin', [d.file(binStubName('script'), _foreignBinStub)]),
    ]).validate();
  });

  test('removes a malformed pub binstub', () async {
    await d.dir(cachePath, [
      d.dir('bin', [d.file(binStubName('script'), _malformedPubBinStub)]),
    ]).create();

    await runPub(
      args: ['cache', 'repair', '--all'],
      error: allOf([
        contains('Error reading binstub for "script":'),
        contains("Invalid 'Package' property."),
      ]),
    );

    await d.dir(cachePath, [
      d.dir('bin', [d.nothing(binStubName('script'))]),
    ]).validate();
  });

  test(
    'preserves a binstub that cannot be decoded',
    () async {
      await d.dir(cachePath, [
        d.dir('bin', [d.file(binStubName('script'), 'placeholder')]),
      ]).create();
      final binStubPath = p.join(
        d.sandbox,
        cachePath,
        'bin',
        binStubName('script'),
      );
      File(binStubPath).writeAsBytesSync([0xff]);

      await runPub(
        args: ['cache', 'repair', '--all'],
        error: contains('Error reading binstub for "script":'),
      );

      expect(File(binStubPath).readAsBytesSync(), [0xff]);
    },
    skip:
        Platform.isWindows
            ? '0xff is valid in Windows system encodings.'
            : false,
  );
}
