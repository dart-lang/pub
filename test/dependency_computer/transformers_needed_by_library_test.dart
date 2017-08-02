// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

void main() {
  test("reports a dependency if the library itself is transformed", () async {
    await d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "dependencies": {
          "foo": {"path": "../foo"}
        },
        "transformers": [
          {
            "foo": {"\$include": "bin/myapp.dart.dart"}
          }
        ]
      }),
      d.dir("bin", [
        d.file("myapp.dart", "import 'package:myapp/lib.dart';"),
      ])
    ]).create();

    await d.dir("foo", [
      d.pubspec({"name": "foo", "version": "1.0.0"}),
      d.dir("lib", [d.file("foo.dart", transformer())])
    ]).create();

    expectLibraryDependencies('myapp|bin/myapp.dart', ['foo']);
  });

  test("reports a dependency if a transformed local file is imported",
      () async {
    await d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "dependencies": {
          "foo": {"path": "../foo"}
        },
        "transformers": [
          {
            "foo": {"\$include": "lib/lib.dart"}
          }
        ]
      }),
      d.dir("lib", [
        d.file("lib.dart", ""),
      ]),
      d.dir("bin", [
        d.file("myapp.dart", "import 'package:myapp/lib.dart';"),
      ])
    ]).create();

    await d.dir("foo", [
      d.pubspec({"name": "foo", "version": "1.0.0"}),
      d.dir("lib", [d.file("foo.dart", transformer())])
    ]).create();

    expectLibraryDependencies('myapp|bin/myapp.dart', ['foo']);
  });

  test("reports a dependency if a transformed foreign file is imported",
      () async {
    await d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "dependencies": {
          "foo": {"path": "../foo"}
        },
      }),
      d.dir("bin", [d.file("myapp.dart", "import 'package:foo/foo.dart';")])
    ]).create();

    await d.dir("foo", [
      d.pubspec({
        "name": "foo",
        "version": "1.0.0",
        "transformers": [
          {
            "foo": {"\$include": "lib/foo.dart"}
          }
        ]
      }),
      d.dir("lib",
          [d.file("foo.dart", ""), d.file("transformer.dart", transformer())])
    ]).create();

    expectLibraryDependencies('myapp|bin/myapp.dart', ['foo']);
  });

  test(
      "doesn't report a dependency if no transformed files are "
      "imported", () async {
    await d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "dependencies": {
          "foo": {"path": "../foo"}
        },
        "transformers": [
          {
            "foo": {"\$include": "lib/lib.dart"}
          }
        ]
      }),
      d.dir("lib", [
        d.file("lib.dart", ""),
        d.file("untransformed.dart", ""),
      ]),
      d.dir("bin", [
        d.file("myapp.dart", "import 'package:myapp/untransformed.dart';"),
      ])
    ]).create();

    await d.dir("foo", [
      d.pubspec({"name": "foo", "version": "1.0.0"}),
      d.dir("lib", [d.file("foo.dart", transformer())])
    ]).create();

    expectLibraryDependencies('myapp|bin/myapp.dart', []);
  });
}
