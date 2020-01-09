// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('recompiles activated executable snapshots', () async {
    await servePackages((builder) {
      builder.serve('foo', '1.0.0', contents: [
        d.dir('bin', [d.file('script.dart', "main(args) => print('ok');")])
      ]);
    });

    await runPub(args: ['global', 'activate', 'foo']);

    await d.dir(cachePath, [
      d.dir('global_packages/foo/bin', [d.file('script.dart.snapshot', 'junk')])
    ]).create();

    await runPub(args: ['cache', 'repair'], output: '''
          Downloading foo 1.0.0...
          Reinstalled 1 package.
          Reactivating foo 1.0.0...
          Precompiling executables...
          Precompiled foo:script.
          Reactivated 1 package.''');

    var pub = await pubRun(global: true, args: ['foo:script']);
    expect(pub.stdout, emits('ok'));
    await pub.shouldExit();
  });
}
