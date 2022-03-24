// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'descriptor.dart' as d;
import 'test_pub.dart';

void main() {
  test('displays deprecation notice', () async {
    await runPub(
      args: ['uploader', 'add'],
      error: '''
Package uploaders are no longer managed from the command line.
Manage uploaders from:

https://pub.dev/packages/<packageName>/admin
''',
      exitCode: 1,
    );

    await d.appDir().create();
    await runPub(
      args: ['uploader', 'add'],
      error: '''
Package uploaders are no longer managed from the command line.
Manage uploaders from:

https://pub.dev/packages/myapp/admin
''',
      exitCode: 1,
    );
  });
}
