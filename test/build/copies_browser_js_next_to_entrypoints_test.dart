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
  test("compiles dart.js and interop.js next to entrypoints", () async {
    await serveBrowserPackage();

    await d.dir(appPath, [
      d.appPubspec({"browser": "1.0.0"}),
      d.dir('foo', [
        d.file('file.dart', 'void main() => print("hello");'),
        d.dir('subdir',
            [d.file('subfile.dart', 'void main() => print("subhello");')])
      ]),
      d.dir('web', [
        d.file('file.dart', 'void main() => print("hello");'),
        d.dir('subweb',
            [d.file('subfile.dart', 'void main() => print("subhello");')])
      ])
    ]).create();

    await pubGet();

    await runPub(
        args: ["build", "foo", "web"],
        output: new RegExp(r'Built 12 files to "build".'));

    await d.dir(appPath, [
      d.dir('build', [
        d.dir('foo', [
          d.file('file.dart.js', isNot(isEmpty)),
          d.dir('packages', [
            d.dir('browser', [
              d.file('dart.js', 'contents of dart.js'),
              d.file('interop.js', 'contents of interop.js')
            ])
          ]),
          d.dir('subdir', [
            d.dir('packages', [
              d.dir('browser', [
                d.file('dart.js', 'contents of dart.js'),
                d.file('interop.js', 'contents of interop.js')
              ])
            ]),
            d.file('subfile.dart.js', isNot(isEmpty)),
          ])
        ]),
        d.dir('web', [
          d.file('file.dart.js', isNot(isEmpty)),
          d.dir('packages', [
            d.dir('browser', [
              d.file('dart.js', 'contents of dart.js'),
              d.file('interop.js', 'contents of interop.js')
            ])
          ]),
          d.dir('subweb', [
            d.dir('packages', [
              d.dir('browser', [
                d.file('dart.js', 'contents of dart.js'),
                d.file('interop.js', 'contents of interop.js')
              ])
            ]),
            d.file('subfile.dart.js', isNot(isEmpty))
          ])
        ])
      ])
    ]).validate();
  });
}
