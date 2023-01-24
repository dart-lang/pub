// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test(r'runs even with an empty environment (eg. no $HOME)', () async {
    final server = await servePackages();
    server.serve('foo', '1.2.3');

    await d.appDir(dependencies: {'foo': 'any'}).create();

    await pubGet(
      environment: {
        '_PUB_TEST_CONFIG_DIR': null,
      },
      includeParentHomeAndPath: false,
    );
  });
}
