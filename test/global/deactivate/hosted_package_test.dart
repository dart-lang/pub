// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../test_pub.dart';

void main() {
  test('deactivates an active hosted package', () async {
    await servePackages((builder) => builder.serve('foo', '1.0.0'));

    await runPub(args: ['global', 'activate', 'foo']);

    await runPub(
        args: ['global', 'deactivate', 'foo'],
        output: 'Deactivated package foo 1.0.0.');
  });
}
