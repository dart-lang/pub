// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart=2.10

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('Report retracted packages', () async {
    await servePackages((builder) => builder
      ..serve('foo', '1.0.0', deps: {'bar': 'any'})
      ..serve('bar', '1.0.0'));
    await d.appDir({'foo': '1.0.0'}).create();
    // await pubGet();

    globalPackageServer
        .add((builder) => builder..retractPackageVersion('bar', '1.0.0'));
    await pubGet(output: '''
Resolving dependencies...
  + bar 1.0.0 (retracted)
  + foo 1.0.0
  Downloading foo 1.0.0...
  Downloading bar 1.0.0...
Changed 2 dependencies!
''');
  });
}
