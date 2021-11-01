// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../test_pub.dart';

void main() {
  test('activating a package installs its dependencies', () async {
    await servePackages((builder) {
      builder.serve('foo', '1.0.0', deps: {'bar': 'any'});
      builder.serve('bar', '1.0.0', deps: {'baz': 'any'});
      builder.serve('baz', '1.0.0');
    });

    await runPub(
        args: ['global', 'activate', 'foo'],
        output: allOf([
          contains('Downloading bar 1.0.0...'),
          contains('Downloading baz 1.0.0...')
        ]));
  });
}
