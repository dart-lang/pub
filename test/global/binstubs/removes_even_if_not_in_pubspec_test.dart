// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('removes all binstubs for package', () async {
    await d.dir('foo', [
      d.pubspec({
        'name': 'foo',
        'executables': {'foo': null}
      }),
      d.dir('bin', [d.file('foo.dart', "main() => print('ok');")])
    ]).create();

    // Create the binstub for foo.
    await runPub(args: ['global', 'activate', '--source', 'path', '../foo']);

    // Remove it from the pubspec.
    await d.dir('foo', [
      d.pubspec({'name': 'foo'})
    ]).create();

    // Deactivate.
    await runPub(args: ['global', 'deactivate', 'foo']);

    // It should still be deleted.
    await d.dir(cachePath, [
      d.dir('bin', [d.nothing(binStubName('foo'))])
    ]).validate();
  });
}
