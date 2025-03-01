// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  forBothPubGetAndUpgrade((command) {
    test('fails gracefully if the url does not resolve', () async {
      await d.dir(appPath, [
        d.appPubspec(
          dependencies: {
            'foo': {
              'hosted': {'name': 'foo', 'url': 'https://invalid-url.foo'},
            },
          },
        ),
      ]).create();

      await pubCommand(
        command,
        error:
            'Got socket error trying to find package foo at '
            'https://invalid-url.foo.',
        exitCode: exit_codes.UNAVAILABLE,
        environment: {'PUB_MAX_HTTP_RETRIES': '2'},
      );
    });
  });
}
