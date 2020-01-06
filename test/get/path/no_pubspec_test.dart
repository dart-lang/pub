// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE d.file.

import 'package:test/test.dart';

import 'package:path/path.dart' as path;
import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('path dependency to non-package directory', () async {
    // Make an empty directory.
    await d.dir('foo').create();
    var fooPath = path.join(d.sandbox, 'foo');

    await d.dir(appPath, [
      d.appPubspec({
        'foo': {'path': fooPath}
      })
    ]).create();

    await pubGet(
        error: RegExp(r'Could not find a file named "pubspec.yaml" '
            r'in "[^\n]*"\.'),
        exitCode: exit_codes.NO_INPUT);
  });
}
