// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('Succeeds running experimental code.', () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '>=2.10.0 <=3.0.0'},
      }),
      d.dir('bin', [
        d.file('script.dart', '''
  main() {
    int? a = int.tryParse('123');
  }
''')
      ])
    ]).create();
    await pubGet(environment: {'_PUB_TEST_SDK_VERSION': '2.10.0'});
    await runPub(
      args: ['run', '--enable-experiment=non-nullable', 'bin/script.dart'],
      environment: {'_PUB_TEST_SDK_VERSION': '2.10.0'},
    );
  });
}
