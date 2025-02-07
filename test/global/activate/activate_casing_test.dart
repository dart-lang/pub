// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test(
    'On case-insensitive systems, will not allow installing ',
    () async {
      final server = await servePackages();
      server.serve(
        'foo',
        '1.0.0',
        contents: [
          d.dir('bin', [d.file('foo.dart', 'main() => print("hi"); ')]),
        ],
      );
      server.serve(
        'Foo',
        '1.0.0',
        contents: [
          d.dir('bin', [d.file('foo.dart', 'main() => print("hi"); ')]),
        ],
      );

      await runPub(args: ['global', 'activate', 'foo']);
      await runPub(
        args: ['global', 'activate', 'Foo'],
        error: '''
You are trying to activate `Foo` but already have `foo` which
differs only by casing. `pub` does not allow that.

Consider `dart pub global deactivate foo`''',
        exitCode: 1,
      );
    },
  );
}
