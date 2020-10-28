// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('Complains nicely about invalid PUB_HOSTED_URL', () async {
    await d.appDir({'foo': 'any'}).create();

    // Get once so it gets cached.
    await pubGet(
        environment: {'PUB_HOSTED_URL': 'abc://bad_scheme.com'},
        error: contains(
            'PUB_HOSTED_URL` must have either the scheme "https://" or "http://".'),
        exitCode: 78);

    await pubGet(
        environment: {'PUB_HOSTED_URL': ''},
        error: contains(
            'PUB_HOSTED_URL` must have either the scheme "https://" or "http://".'),
        exitCode: 78);
  });
}
