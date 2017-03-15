// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:scheduled_test/scheduled_stream.dart';
import 'package:scheduled_test/scheduled_test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

main() {
  integration('recompiles a script if the snapshot is out-of-date', () {
    servePackages((builder) {
      builder.serve("foo", "1.0.0", contents: [
        d.dir("bin", [d.file("script.dart", "main(args) => print('ok');")])
      ]);
    });

    schedulePub(args: ["global", "activate", "foo"]);

    d.dir(cachePath, [
      d.dir('global_packages', [
        d.dir('foo', [
          d.dir('bin', [d.outOfDateSnapshot('script.dart.snapshot')])
        ])
      ])
    ]).create();

    var pub = pubRun(global: true, args: ["foo:script"]);
    // In the real world this would just print "hello!", but since we collect
    // all output we see the precompilation messages as well.
    pub.stdout.expect("Precompiling executables...");
    pub.stdout.expect(consumeThrough("ok"));
    pub.shouldExit();

    d.dir(cachePath, [
      d.dir('global_packages', [
        d.dir('foo', [
          d.dir('bin', [d.matcherFile('script.dart.snapshot', contains('ok'))])
        ])
      ])
    ]).validate();
  });
}
