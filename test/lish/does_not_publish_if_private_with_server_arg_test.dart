// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('does not publish if the package is private even if a server '
      'argument is provided', () async {
    await d.validPackage(pubspecExtras: {'publish_to': 'none'}).create();

    await runPub(
      args: ['lish'],
      error: contains('A private package cannot be published.'),
      environment: {'PUB_HOSTED_URL': 'http://example.com'},
      exitCode: exit_codes.DATA,
    );
  });
}
