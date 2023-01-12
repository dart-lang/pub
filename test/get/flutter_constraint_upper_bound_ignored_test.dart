// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('pub get succeeds despite of "invalid" flutter upper bound', () async {
    final fakeFlutterRoot =
        d.dir('fake_flutter_root', [d.file('version', '1.23.0')]);
    await fakeFlutterRoot.create();
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'flutter': '>=0.5.0 <1.0.0'}
      }),
    ]).create();

    await pubGet(
      exitCode: exit_codes.SUCCESS,
      environment: {'FLUTTER_ROOT': fakeFlutterRoot.io.path},
    );
  });
}
