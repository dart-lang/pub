// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('`pub get` inside the cache fails gracefully', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0', pubspec: {
      'name': 'foo',
      'version': '1.0.0',
      'environment': {'sdk': '>=0.1.2+3 <0.2.0'}
    });
    await d.appDir({'foo': 'any'}).create();

    await pubGet();

    await pubGet(
        workingDirectory: p.join(d.sandbox, d.hostedCachePath(), 'foo-1.0.0'));
  });
}
