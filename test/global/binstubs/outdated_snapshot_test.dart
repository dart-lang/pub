// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:pub/src/io.dart';
import 'package:scheduled_test/scheduled_process.dart';
import 'package:scheduled_test/scheduled_stream.dart';
import 'package:scheduled_test/scheduled_test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';
import 'utils.dart';

main() {
  integration("a binstub runs 'pub global run' for an outdated snapshot", () {
    servePackages((builder) {
      builder.serve("foo", "1.0.0", pubspec: {
        "executables": {"foo-script": "script"}
      }, contents: [
        d.dir(
            "bin", [d.file("script.dart", "main(args) => print('ok \$args');")])
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

    var process = new ScheduledProcess.start(
        p.join(sandboxDir, cachePath, "bin", binStubName("foo-script")),
        ["arg1", "arg2"],
        environment: getEnvironment());

    process.stderr.expect(startsWith("Wrong script snapshot version"));
    process.stdout.expect(consumeThrough("ok [arg1, arg2]"));
    process.shouldExit();

    d.dir(cachePath, [
      d.dir('global_packages/foo/bin', [
        d.binaryMatcherFile(
            'script.dart.snapshot',
            isNot(
                equals(readBinaryFile(testAssetPath('out-of-date.snapshot')))))
      ])
    ]).validate();
  });
}
