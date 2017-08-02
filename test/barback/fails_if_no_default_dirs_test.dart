// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../descriptor.dart' as d;
import 'utils.dart';

main() {
  setUp(() => d.appDir().create());

  pubBuildAndServeShouldFail(
      "if no directories were passed and no default "
      "ones exist",
      args: [],
      buildError: 'Your package must have a "web" directory,\n'
          'or you must specify the source directories.',
      serveError: 'Your package must have "web" and/or "test" directories,\n'
          'or you must specify the source directories.',
      exitCode: exit_codes.DATA);
}
