// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

void main() {
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
          },
          "myapp"
        ]
      }),
      d.dir("lib", [
        d.file("myapp.dart", ""),
        d.file("lib.dart", ""),
        d.file("transformer.dart", transformer(["lib.dart"]))
      ])
    ]).create();

    await d.dir("foo", [
      d.pubspec({"name": "foo", "version": "1.0.0"}),
      d.dir("lib", [d.file("foo.dart", transformer())])
    ]).create();

    expectDependencies({
      'myapp': ['foo'],
      'foo': []
    });
  });

  test("reports a dependency if a transformed foreign file is imported",
      () async {
    await d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "dependencies": {
          "foo": {"path": "../foo"}
        },
        "transformers": ["myapp"]
      }),
      d.dir("lib", [
        d.file("myapp.dart", ""),
        d.file("transformer.dart", transformer(["package:foo/foo.dart"]))
      ])
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

    expectDependencies({
      'myapp': ['foo'],
      'foo': []
    });
  });

  test(
      "reports a dependency if a transformed external package file is "
      "imported from an export", () async {
    await d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "dependencies": {
          "foo": {"path": "../foo"}
        },
        "transformers": ["myapp"]
      }),
      d.dir("lib", [
        d.file("myapp.dart", ""),
        d.file("transformer.dart", transformer(["local.dart"])),
        d.file("local.dart", "export 'package:foo/foo.dart';")
      ])
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

    expectDependencies({
      'myapp': ['foo'],
      'foo': []
    });
  });

  test(
      "reports a dependency if a transformed foreign file is "
      "transitively imported", () async {
    await d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "dependencies": {
          "foo": {"path": "../foo"}
        },
        "transformers": ["myapp"]
      }),
      d.dir("lib", [
        d.file("myapp.dart", ""),
        d.file("transformer.dart", transformer(["local.dart"])),
        d.file("local.dart", "import 'package:foo/foreign.dart';")
      ])
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
      d.dir("lib", [
        d.file("foo.dart", ""),
        d.file("transformer.dart", transformer()),
        d.file("foreign.dart", "import 'foo.dart';")
      ])
    ]).create();

    expectDependencies({
      'myapp': ['foo'],
      'foo': []
    });
  });

  test(
      "reports a dependency if a transformed foreign file is "
      "transitively imported across packages", () async {
    await d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "dependencies": {
          "foo": {"path": "../foo"}
        },
        "transformers": ["myapp"]
      }),
      d.dir("lib", [
        d.file("myapp.dart", ""),
        d.file("transformer.dart", transformer(["package:foo/foo.dart"])),
      ])
    ]).create();

    await d.dir("foo", [
      d.pubspec({
        "name": "foo",
        "version": "1.0.0",
        "dependencies": {
          "bar": {"path": "../bar"}
        }
      }),
      d.dir("lib", [d.file("foo.dart", "import 'package:bar/bar.dart';")])
    ]).create();

    await d.dir("bar", [
      d.pubspec({
        "name": "bar",
        "version": "1.0.0",
        "transformers": [
          {
            "bar": {"\$include": "lib/bar.dart"}
          }
        ]
      }),
      d.dir("lib",
          [d.file("bar.dart", ""), d.file("transformer.dart", transformer())])
    ]).create();

    expectDependencies({
      'myapp': ['bar'],
      'bar': []
    });
  });

  test(
      "reports a dependency if an imported file is transformed by a "
      "different package", () async {
    await d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "dependencies": {
          "foo": {"path": "../foo"}
        },
        "transformers": [
          {
            "foo": {'\$include': 'lib/local.dart'}
          },
          "myapp"
        ]
      }),
      d.dir("lib", [
        d.file("myapp.dart", ""),
        d.file("transformer.dart", transformer(["local.dart"])),
        d.file("local.dart", "")
      ])
    ]).create();

    await d.dir("foo", [
      d.pubspec({"name": "foo", "version": "1.0.0"}),
      d.dir("lib", [d.file("transformer.dart", transformer())])
    ]).create();

    expectDependencies({
      'myapp': ['foo'],
      'foo': []
    });
  });
}
