// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

const _outdatedBinstub = '''
#!/usr/bin/env sh
# This file was created by pub v0.1.2-3.
# Package: foo
# Version: 1.0.0
# Executable: foo-script
# Script: script
dart "/path/to/.pub-cache/global_packages/foo/bin/script.dart.snapshot" "\$@"
''';

void main() {
  test('updates an outdated binstub script', () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      pubspec: {
        'executables': {'foo-script': 'script'},
      },
      contents: [
        d.dir('bin', [
          d.file('script.dart', "main(args) => print('ok \$args');"),
        ]),
      ],
    );

    await runPub(args: ['global', 'activate', 'foo']);

    await d.dir(cachePath, [
      d.dir('bin', [d.file(binStubName('foo-script'), _outdatedBinstub)]),
    ]).create();

    // Repair them.
    await runPub(
      args: ['cache', 'repair'],
      output: '''
          Reinstalled 1 package.
          Reactivating foo 1.0.0...
          Downloading packages...
          Building package executables...
          Built foo:script.
          Installed executable foo-script.
          Reactivated 1 package.''',
    );

    // The broken versions should have been replaced.
    await d.dir(cachePath, [
      d.dir('bin', [
        d.file(
          binStubName('foo-script'),
          contains('This file was created by pub v3.1.2+3'),
        ),
      ]),
    ]).validate();
  });
}
