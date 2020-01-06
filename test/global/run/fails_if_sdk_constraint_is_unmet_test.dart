// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test("fails if the current SDK doesn't match the constraint", () async {
    await servePackages((builder) {
      builder.serve('foo', '1.0.0', contents: [
        d.dir('bin', [d.file('script.dart', "main(args) => print('ok');")])
      ]);
    });

    await runPub(args: ['global', 'activate', 'foo']);

    await d.hostedCache([
      d.dir('foo-1.0.0', [d.libPubspec('foo', '1.0.0', sdk: '0.5.6')])
    ]).create();

    // Make the snapshot out-of-date, too, so that we load the pubspec with the
    // SDK constraint in the first place. In practice, the VM snapshot
    // invalidation logic is based on the version anyway, so this is a safe
    // assumption.
    await d.dir(cachePath, [
      d.dir('global_packages', [
        d.dir('foo', [
          d.dir('bin', [d.outOfDateSnapshot('script.dart.snapshot')])
        ])
      ])
    ]).create();

    await runPub(
        args: ['global', 'run', 'foo:script'],
        error: contains("foo 1.0.0 doesn't support Dart 0.1.2+3."),
        exitCode: exit_codes.DATA);
  });
}
