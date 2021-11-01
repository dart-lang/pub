// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('the binstubs runs pub global run if there is no snapshot', () async {
    await d.dir('foo', [
      d.pubspec({
        'name': 'foo',
        'executables': {'foo-script': 'script'}
      }),
      d.dir('bin', [d.file('script.dart', "main() => print('ok');")])
    ]).create();

    // Path packages are mutable, so no snapshot is created.
    await runPub(
        args: ['global', 'activate', '--source', 'path', '../foo'],
        output: contains('Installed executable foo-script.'));

    await d.dir(cachePath, [
      d.dir('bin', [
        d.file(binStubName('foo-script'), contains('pub global run foo:script'))
      ])
    ]).validate();
  });
}
