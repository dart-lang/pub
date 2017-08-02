// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../descriptor.dart' as d;
import 'utils.dart';

main() {
  setUp(() => d.appDir().create());

  var libSub = path.join("lib", "sub");
  pubBuildAndServeShouldFail("if given directories are not allowed",
      args: [libSub, "lib"],
      error: 'Directories "$libSub" and "lib" are not allowed.',
      exitCode: exit_codes.USAGE);
}
