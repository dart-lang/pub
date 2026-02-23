// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'package:pub/src/path.dart';
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('We only allow activating lower-case package names', () async {
    final server = await servePackages();
    server.serve(
      'Foo',
      '1.0.0',
      contents: [
        d.dir('bin', [d.file('foo.dart', 'main() => print("hi"); ')]),
      ],
    );

    await d.dir('foo', [d.libPubspec('Foo', '1.0.0')]).create();
    await runPub(
      args: ['global', 'activate', 'Foo'],
      error: '''
You can only activate packages with lower-case names.

Did you mean `foo`?''',
      exitCode: 1,
    );

    await runPub(
      args: ['global', 'activate', '-spath', p.join(d.sandbox, 'foo')],
      error: '''
You can only activate packages with lower-case names.

Did you mean `foo`?''',
      exitCode: 1,
    );
  });
}
