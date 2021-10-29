// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('warns if the binstub directory is not on the path', () async {
    await servePackages((builder) {
      builder.serve('foo', '1.0.0', pubspec: {
        'executables': {'some-dart-script': 'script'}
      }, contents: [
        d.dir(
            'bin', [d.file('script.dart', "main(args) => print('ok \$args');")])
      ]);
    });

    await runPub(
        args: ['global', 'activate', 'foo'],
        error: contains('is not on your path'));
  });
}
