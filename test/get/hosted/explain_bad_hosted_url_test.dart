// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('Complains nicely about invalid PUB_HOSTED_URL', () async {
    await d.appDir(dependencies: {'foo': 'any'}).create();

    // Get once so it gets cached.
    await pubGet(
      environment: {'PUB_HOSTED_URL': 'abc://bad_scheme.com'},
      error: allOf(
        contains('PUB_HOSTED_URL'),
        contains('url scheme must be https:// or http://'),
      ),
      exitCode: 78,
    );

    await pubGet(
      environment: {'PUB_HOSTED_URL': ''},
      error: allOf(
        contains('PUB_HOSTED_URL'),
        contains('url scheme must be https:// or http://'),
      ),
      exitCode: 78,
    );
  });

  test('Allows PUB_HOSTED_URL to end with a slash', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');
    await d.appDir(dependencies: {'foo': 'any'}).create();

    await pubGet(
      environment: {'PUB_HOSTED_URL': '${globalServer.url}/'},
    );
  });
}
