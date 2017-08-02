// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

main() {
  setUp(() {
    return d.dir(appPath, [
      d.appPubspec(),
      d.dir("bar", [d.file("file.txt", "contents")])
    ]).create();
  });

  pubBuildAndServeShouldFail("if a specified directory doesn't exist",
      args: ["foo", "bar", "baz"],
      error: 'Directories "foo" and "baz" do not exist.',
      exitCode: exit_codes.DATA);
}
