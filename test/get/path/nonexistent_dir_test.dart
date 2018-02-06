// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE d.file.

@Skip()

import 'package:test/test.dart';

import 'package:path/path.dart' as path;
import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

main() {
  test('path dependency to non-existent directory', () async {
    var badPath = path.join(d.sandbox, "bad_path");

    await d.dir(appPath, [
      d.appPubspec({
        "foo": {"path": badPath}
      })
    ]).create();

    await pubGet(error: """
        Could not find package foo at "$badPath".
        Depended on by:
        - myapp""", exitCode: exit_codes.NO_INPUT);
  });
}
