// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart' as exit_codes;

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('--dry-run package validation on valid package has no warnings',
      () async {
    await d.validPackage().create();

    await servePackages();
    var pub = await startPublish(globalServer, args: ['--dry-run']);

    await pub.shouldExit(exit_codes.SUCCESS);
    expect(pub.stderr, emitsThrough('Package has 0 warnings.'));
  });
}
