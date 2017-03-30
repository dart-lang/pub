// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'package:scheduled_test/scheduled_test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import '../serve/utils.dart';

main() {
  setUp(() {
    d.dir("foo", [
      d.libPubspec("foo", "0.0.1"),
      d.dir("lib", [d.file("lib.dart", "main() => print('foo');")])
    ]).create();

    d.dir(appPath, [
      d.appPubspec({
        "foo": {"path": "../foo"}
      })
    ]).create();

    pubGet();
  });

  tearDown(() {
    endPubServe();
  });

  integration("dart2js ignores a Dart entrypoint in a dependency", () {
    pubServe();
    requestShould404("web/packages/foo/lib.dart.js");
  });

  integration("dartdevc ignores a Dart entrypoint in a dependency", () {
    pubServe(args: ["--compiler=dartdevc"]);
    requestShould404("web/packages/foo/lib.dart.js");
  });
}
