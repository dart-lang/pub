// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Dart2js can take a long time to compile dart code, so we increase the timeout
// to cope with that.
@Timeout.factor(3)
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

main() {
  // This is a regression test for http://dartbug.com/16617.

  test(
      "compiles dart.js and interop.js next to entrypoints when "
      "browser is a dev dependency", () async {
    await serveBrowserPackage();

    await d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "dev_dependencies": {"browser": "any"}
      }),
      d.dir('web', [d.file('file.dart', 'void main() => print("hello");')])
    ]).create();

    await pubGet();

    await runPub(
        args: ["build", "--all"],
        output: new RegExp(r'Built 3 files to "build".'));

    await d.dir(appPath, [
      d.dir('build', [
        d.dir('web', [
          d.dir('packages', [
            d.dir('browser', [
              d.file('dart.js', 'contents of dart.js'),
              d.file('interop.js', 'contents of interop.js')
            ])
          ])
        ])
      ])
    ]).validate();
  });
}
