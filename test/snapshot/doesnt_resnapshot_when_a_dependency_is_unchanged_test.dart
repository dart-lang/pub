// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

main() {
  test(
      "doesn't recreate a snapshot when no dependencies of a package "
      "have changed", () async {
    await servePackages((builder) {
      builder.serve("foo", "1.2.3", deps: {
        "bar": "any"
      }, contents: [
        d.dir("bin", [d.file("hello.dart", "void main() => print('hello!');")])
      ]);
      builder.serve("bar", "1.2.3");
    });

    await d.appDir({"foo": "1.2.3"}).create();

    await pubGet(output: contains("Precompiled foo:hello."));

    await pubUpgrade(output: isNot(contains("Precompiled foo:hello.")));

    await d.dir(p.join(appPath, '.pub', 'bin'), [
      d.file('sdk-version', '0.1.2+3\n'),
      d.dir('foo', [d.file('hello.dart.snapshot', contains('hello!'))])
    ]).validate();
  });
}
