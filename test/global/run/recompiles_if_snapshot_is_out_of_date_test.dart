// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('recompiles a script if the snapshot is out-of-date', () async {
    await servePackages((builder) {
      builder.serve('foo', '1.0.0', contents: [
        d.dir('bin', [d.file('script.dart', "main(args) => print('ok');")])
      ]);
    });

    await runPub(args: ['global', 'activate', 'foo']);

    await d.dir(cachePath, [
      d.dir('global_packages', [
        d.dir('foo', [
          d.dir('bin', [d.outOfDateSnapshot('script.dart.snapshot.dart2')])
        ])
      ])
    ]).create();

    var pub = await pubRun(global: true, args: ['foo:script']);
    // In the real world this would just print "hello!", but since we collect
    // all output we see the precompilation messages as well.
    expect(pub.stdout, emits('Precompiling executables...'));
    expect(pub.stdout, emitsThrough('ok'));
    await pub.shouldExit();

    await d.dir(cachePath, [
      d.dir('global_packages', [
        d.dir('foo', [
          d.dir('bin', [d.file('script.dart.snapshot.dart2', contains('ok'))])
        ])
      ])
    ]).validate();
  });
}
