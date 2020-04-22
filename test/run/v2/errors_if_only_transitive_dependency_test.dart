// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('Errors if the script is in a non-immediate dependency.', () async {
    await d.dir('foo', [
      d.libPubspec('foo', '1.0.0'),
      d.dir('bin', [d.file('bar.dart', "main() => print('foobar');")])
    ]).create();

    await d.dir('bar', [
      d.libPubspec('bar', '1.0.0', deps: {
        'foo': {'path': '../foo'}
      })
    ]).create();

    await d.dir(appPath, [
      d.appPubspec({
        'bar': {'path': '../bar'}
      })
    ]).create();

    await pubGet();

    var pub = await pubRunV2(args: ['foo:script']);
    expect(pub.stderr, emits('Package "foo" is not an immediate dependency.'));
    expect(pub.stderr,
        emits('Cannot run executables in transitive dependencies.'));
    await pub.shouldExit(exit_codes.DATA);
  });
}
