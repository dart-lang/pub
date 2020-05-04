// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('Errors if the script is in an unknown package.', () async {
    await d.dir(appPath, [d.appPubspec()]).create();

    await pubGet();
    var pub = await pubRunV2(args: ['foo:script']);
    expect(
        pub.stderr,
        emits('Could not find package "foo". Did you forget to add a '
            'dependency?'));
    await pub.shouldExit(exit_codes.DATA);
  });
}
