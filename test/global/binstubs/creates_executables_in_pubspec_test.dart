// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('creates binstubs for each executable in the pubspec', () async {
    await servePackages((builder) {
      builder.serve('foo', '1.0.0', pubspec: {
        'executables': {'one': null, 'two-renamed': 'second'}
      }, contents: [
        d.dir('bin', [
          d.file('one.dart', "main(args) => print('one');"),
          d.file('second.dart', "main(args) => print('two');"),
          d.file('nope.dart', "main(args) => print('nope');")
        ])
      ]);
    });

    await runPub(
        args: ['global', 'activate', 'foo'],
        output: contains('Installed executables one and two-renamed.'));

    await d.dir(cachePath, [
      d.dir('bin', [
        d.file(binStubName('one'), contains('one')),
        d.file(binStubName('two-renamed'), contains('second')),
        d.nothing(binStubName('two')),
        d.nothing(binStubName('nope'))
      ])
    ]).validate();
  });
}
