// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('the binstubs runs a precompiled snapshot if present', () async {
    await servePackages((builder) {
      builder.serve('foo', '1.0.0', pubspec: {
        'executables': {'foo-script': 'script'}
      }, contents: [
        d.dir('bin', [d.file('script.dart', "main(args) => print('ok');")])
      ]);
    });

    await runPub(args: ['global', 'activate', 'foo']);

    await d.dir(cachePath, [
      d.dir('bin',
          [d.file(binStubName('foo-script'), contains('script.dart.snapshot'))])
    ]).validate();
  });
}
