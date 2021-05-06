// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart=2.10

import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('an explicit --server argument overrides a "publish_to" url', () async {
    // Create a real server that can reject requests because validators will
    // try to ping it, and will use multiple retries when doing so.
    final packageServer = await DescriptorServer.start();
    final fakePackageServer = 'http://localhost:${packageServer.port}';

    var pkg = packageMap('test_pkg', '1.0.0');
    pkg['publish_to'] = 'http://pubspec.com';
    await d.dir(appPath, [d.pubspec(pkg)]).create();

    await runPub(
        args: ['lish', '--dry-run', '--server', fakePackageServer],
        output: contains(fakePackageServer),
        exitCode: exit_codes.DATA);

    await packageServer.close();
  });
}
