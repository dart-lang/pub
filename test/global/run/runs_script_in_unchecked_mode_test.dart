// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

const _script = '''
main() {
  assert(false);
  print("no checks");
}
''';

void main() {
  test('runs a script in unchecked mode by default', () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      contents: [
        d.dir('bin', [d.file('script.dart', _script)])
      ],
    );

    await runPub(args: ['global', 'activate', 'foo']);

    var pub = await pubRun(global: true, args: ['foo:script']);
    expect(pub.stdout, emits('no checks'));
    await pub.shouldExit();
  });
}
