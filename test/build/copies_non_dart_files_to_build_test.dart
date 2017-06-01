// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

main() {
  test("copies non-Dart files to build/", () async {
    await servePackages((builder) => builder.serve("browser", "1.0.0"));

    await d.dir(appPath, [
      // A browser dependency with no entrypoints shouldn't cause dart.js to be
      // copied in.
      d.appPubspec({"browser": "1.0.0"}),
      d.dir('web', [
        d.file('file.txt', 'contents'),
        d.dir('subdir', [d.file('subfile.txt', 'subcontents')])
      ])
    ]).create();

    await pubGet();
    await runPub(
        args: ["build"], output: new RegExp(r'Built 2 files to "build".'));

    await d.dir(appPath, [
      d.dir('build', [
        d.dir('web', [
          d.nothing('packages'),
          d.file('file.txt', 'contents'),
          d.dir('subdir', [d.file('subfile.txt', 'subcontents')])
        ])
      ])
    ]).validate();
  });
}
