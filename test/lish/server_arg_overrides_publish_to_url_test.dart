// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('an explicit --server argument overrides a "publish_to" url', () async {
    var pkg = packageMap('test_pkg', '1.0.0');
    pkg['publish_to'] = 'http://pubspec.com';
    await d.dir(appPath, [d.pubspec(pkg)]).create();

    await runPub(
        args: ['lish', '--dry-run', '--server', 'http://arg.com'],
        output: contains('http://arg.com'),
        exitCode: exit_codes.DATA);
  });
}
