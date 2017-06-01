// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout.factor(3)
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

main() {
  // This is a regression test for http://dartbug.com/16617.

  test(
      "compiles dart.js and interop.js next to entrypoints when "
      "browser is a dependency_override", () async {
    await serveBrowserPackage();

    await d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "dependency_overrides": {"browser": "any"}
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
