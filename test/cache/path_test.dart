// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('running pub cache path', () async {
    final cache = p.join(d.sandbox, cachePath);
    await runPub(args: ['cache', 'path'], output: cache);
  });
  test(
    'running pub cache path with PUB_CACHE set prints the right path',
    () async {
      final envCache = p.join(d.sandbox, 'otherCache');
      await runPub(
        args: ['cache', 'path'],
        environment: {'PUB_CACHE': envCache},
        output: envCache,
      );
    },
  );
}
