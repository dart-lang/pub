// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/path.dart';
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

import '../../descriptor.dart';
import '../../test_pub.dart';
import '../binstubs/utils.dart';

void main() {
  test('activating a package from path from a workspace works', () async {
    await servePackages();
    await dir(appPath, [
      libPubspec(
        'workspace',
        '1.2.3',
        extras: {
          'workspace': ['pkgs/foo'],
        },
        sdk: '^3.5.0',
      ),
      dir('pkgs', [
        dir('foo', [
          libPubspec(
            'foo',
            '1.1.1',
            extras: {
              'executables': {'foo-script': 'foo'},
            },
            resolutionWorkspace: true,
          ),
          dir('bin', [file('foo.dart', "main() => print('path');")]),
        ]),
      ]),
    ]).create();

    await runPub(
      args: ['global', 'activate', '-spath', 'pkgs/foo'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
    );

    await runPub(
      args: ['global', 'run', 'foo'],
      output: contains('path'),
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
    );

    final process = await TestProcess.start(
      p.join(sandbox, cachePath, 'bin', binStubName('foo-script')),
      [],
      environment: {...getEnvironment(), '_PUB_TEST_SDK_VERSION': '3.5.0'},
    );

    expect(process.stdout, emitsThrough('path'));
    await process.shouldExit();
  });
}
