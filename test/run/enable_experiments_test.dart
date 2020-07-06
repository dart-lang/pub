// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('Succeeds running experimental code.', () async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir('bin', [
        d.file('script.dart', '''
  main() {
    int? a = int.tryParse('123');
  }
''')
      ])
    ]).create();
    await pubGet();
    await runPub(
        args: ['run', '--enable-experiment=non-nullable', 'bin/script.dart']);
  },
      skip: Platform.version.contains('2.9')
          ? false
          : 'experiment non-nullable only available for test on sdk 2.9');
}
