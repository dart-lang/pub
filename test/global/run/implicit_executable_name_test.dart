// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('defaults to the package name if the script is omitted', () async {
    await servePackages((builder) {
      builder.serve('foo', '1.0.0', contents: [
        d.dir('bin', [d.file('foo.dart', "main(args) => print('foo');")])
      ]);
    });

    await runPub(args: ['global', 'activate', 'foo']);

    var pub = await pubRun(global: true, args: ['foo']);
    expect(pub.stdout, emits('foo'));
    await pub.shouldExit();
  });
}
