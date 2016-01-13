// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;

import '../descriptor.dart' as d;
import '../test_pub.dart';

main() {
  integration("doesn't create a snapshot for a path dependency", () {
    d.dir("foo", [
      d.libPubspec("foo", "1.2.3"),
      d.dir("bin", [
        d.dir("bin", [d.file("hello.dart", "void main() => print('hello!');")])
      ])
    ]).create();

    d.appDir({"foo": {"path": "../foo"}}).create();

    pubGet();

    d.nothing(p.join(appPath, '.pub', 'bin')).validate();
  });
}
