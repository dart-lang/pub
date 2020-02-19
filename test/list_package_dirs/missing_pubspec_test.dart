// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:pub/src/io.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  // This is a regression test for #20065.
  test('reports a missing pubspec error using JSON', () async {
    await d.dir(appPath).create();

    await runPub(args: [
      'list-package-dirs',
      '--format=json'
    ], outputJson: {
      'error': 'Could not find a file named "pubspec.yaml" in '
          '"${canonicalize(path.join(d.sandbox, appPath))}".',
      'path': canonicalize(path.join(d.sandbox, appPath, 'pubspec.yaml'))
    }, exitCode: exit_codes.NO_INPUT);
  });
}
