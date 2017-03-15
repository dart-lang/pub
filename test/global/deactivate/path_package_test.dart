// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:pub/src/io.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

main() {
  integration('deactivates an active path package', () {
    d.dir("foo", [
      d.libPubspec("foo", "1.0.0"),
      d.dir("bin", [d.file("foo.dart", "main() => print('ok');")])
    ]).create();

    schedulePub(args: ["global", "activate", "--source", "path", "../foo"]);

    var path = canonicalize(p.join(sandboxDir, "foo"));
    schedulePub(
        args: ["global", "deactivate", "foo"],
        output: 'Deactivated package foo 1.0.0 at path "$path".');
  });
}
