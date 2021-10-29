// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('removes binstubs when the package is deactivated', () async {
    await servePackages((builder) {
      builder.serve('foo', '1.0.0', pubspec: {
        'executables': {'one': null, 'two': null}
      }, contents: [
        d.dir('bin', [
          d.file('one.dart', "main(args) => print('one');"),
          d.file('two.dart', "main(args) => print('two');")
        ])
      ]);
    });

    await runPub(args: ['global', 'activate', 'foo']);
    await runPub(args: ['global', 'deactivate', 'foo']);

    await d.dir(cachePath, [
      d.dir(
          'bin', [d.nothing(binStubName('one')), d.nothing(binStubName('two'))])
    ]).validate();
  });
}
