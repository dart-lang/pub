// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';
import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('The upgrade report handles a package becoming root', () async {
    await servePackages((builder) {
      builder.serve('foo', '1.0.0', deps: {'myapp': 'any'});
      builder.serve('myapp', '1.0.0', deps: {'foo': 'any'});
    });

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myappx',
        'version': '1.0.0',
        'dependencies': {'foo': 'any'},
      })
    ]).create();

    await pubGet();

    // Rename the package
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'version': '1.0.1',
        'dependencies': {'foo': 'any'},
      })
    ]).create();
    await pubUpgrade();
  });
}
