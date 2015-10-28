// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:scheduled_test/scheduled_test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

main() {
  integration("fails if the current SDK doesn't match the constraint", () {
    servePackages((builder) {
      builder.serve("foo", "1.0.0", contents: [
        d.dir("bin", [
          d.file("script.dart", "main(args) => print('ok');")
        ])
      ]);
    });

    schedulePub(args: ["global", "activate", "foo"]);

    d.hostedCache([
      d.dir("foo-1.0.0", [
        d.libPubspec("foo", "1.0.0", sdk: "0.5.6")
      ])
    ]).create();

    // Make the snapshot out-of-date, too, so that we load the pubspec with the
    // SDK constraint in the first place. In practice, the VM snapshot
    // invalidation logic is based on the version anyway, so this is a safe
    // assumption.
    d.dir(cachePath, [
      d.dir('global_packages', [
        d.dir('foo', [
          d.dir('bin', [d.outOfDateSnapshot('script.dart.snapshot')])
        ])
      ])
    ]).create();

    schedulePub(args: ["global", "run", "foo:script"],
        error: contains("foo 1.0.0 doesn't support Dart 0.1.2+3."),
        exitCode: exit_codes.DATA);
  });
}
