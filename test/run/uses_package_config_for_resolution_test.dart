// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test(
      'Succeeds running script from dependency even though PUB_CACHE has changed.',
      () async {
    await d.appDir({'foo': 'any'}).create();
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      contents: [
        d.dir(
          'bin',
          [
            d.file('script.dart', '''main() {print('hello');}'''),
          ],
        )
      ],
    );
    await pubGet(environment: {});
    await runPub(
        args: ['run', 'foo:script'],
        environment: {'PUB_CACHE': '/not/the/real/pub/cache'},
        output: contains('hello'));
  });
}
