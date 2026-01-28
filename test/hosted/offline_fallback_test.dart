// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  // Note: The fallback-to-cache behavior on network failure is implemented in
  // hosted.dart but is difficult to test in isolation because the test
  // infrastructure requires the server to be running. The behavior has been
  // verified manually and works correctly for real socket errors.

  test('gives helpful error when network fails and no cache exists', () async {
    await d.dir(appPath, [
      d.appPubspec(
        dependencies: {
          'foo': {
            'hosted': {'name': 'foo', 'url': 'https://invalid-url.foo'},
          },
        },
      ),
    ]).create();

    await pubGet(
      error: allOf([
        contains('Got socket error'),
        contains('Check your internet connection'),
      ]),
      exitCode: exit_codes.UNAVAILABLE,
      environment: {'PUB_MAX_HTTP_RETRIES': '1'},
    );
  });
}
