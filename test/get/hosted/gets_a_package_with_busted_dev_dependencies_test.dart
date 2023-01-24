// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  // Regression test for issue 22194.
  test(
      'gets a dependency with broken dev dependencies from a pub '
      'server', () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '1.2.3',
      pubspec: {
        'dev_dependencies': {
          'busted': {'not a real source': null}
        }
      },
    );

    await d.appDir(dependencies: {'foo': '1.2.3'}).create();

    await pubGet();

    await d.cacheDir({'foo': '1.2.3'}).validate();
    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '1.2.3'),
    ]).validate();
  });
}
