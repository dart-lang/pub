// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:pub/src/io.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

main() {
  test('activates a package at a local path', () async {
    await d.dir("foo", [
      d.libPubspec("foo", "1.0.0"),
      d.dir("bin", [d.file("foo.dart", "main() => print('ok');")])
    ]).create();

    var path = canonicalize(p.join(d.sandbox, "foo"));
    await runPub(
        args: ["global", "activate", "--source", "path", "../foo"],
        output: endsWith('Activated foo 1.0.0 at path "$path".'));
  });
}
