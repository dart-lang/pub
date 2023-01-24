// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('pub get with PUB_SUMMARY_ONLY will only print a summary', () async {
    (await servePackages()).serve('foo', '1.0.0');
    await d.appDir(dependencies: {'foo': 'any'}).create();

    await pubGet(
      output: 'Resolving dependencies...\nGot dependencies.',
      silent: contains('+ foo 1.0.0'),
      environment: {'PUB_SUMMARY_ONLY': '1'},
    );
  });
}
