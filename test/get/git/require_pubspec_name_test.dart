// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test(
      'requires the dependency to have a pubspec with a name '
      'field', () async {
    ensureGit();

    await d.git('foo.git', [d.libDir('foo'), d.pubspec({})]).create();

    await d.appDir({
      'foo': {'git': '../foo.git'}
    }).create();

    await pubGet(
        error: contains('Missing the required "name" field.'),
        exitCode: exit_codes.DATA);
  });
}
