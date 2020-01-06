// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('uses the publish_to URL', () async {
    var pkg = packageMap('test_pkg', '1.0.0');
    pkg['publish_to'] = 'http://example.com';
    await d.dir(appPath, [d.pubspec(pkg)]).create();

    await runPub(
        args: ['lish', '--dry-run'],
        output: contains('Publishing test_pkg 1.0.0 to http://example.com'),
        exitCode: exit_codes.DATA);
  });
}
