// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE d.file.

import 'package:test/test.dart';

import 'package:path/path.dart' as p;
import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  // Regression test for issue 20103.
  test('path dependency to an empty pubspec', () async {
    await d.dir('foo', [d.libDir('foo'), d.file('pubspec.yaml', '')]).create();

    await d.dir(appPath, [
      d.appPubspec({
        'foo': {'path': '../foo'}
      })
    ]).create();

    await pubGet(
        exitCode: exit_codes.DATA,
        error:
            'Error on line 1, column 1 of ${p.join('..', 'foo', 'pubspec.yaml')}: '
            'Missing the required "name" field.');
  });
}
