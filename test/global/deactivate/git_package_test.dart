// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('deactivates an active Git package', () async {
    ensureGit();

    await d.git('foo.git', [
      d.libPubspec('foo', '1.0.0'),
      d.dir('bin', [d.file('foo.dart', "main() => print('ok');")])
    ]).create();

    await runPub(args: ['global', 'activate', '-sgit', '../foo.git']);

    await runPub(
        args: ['global', 'deactivate', 'foo'],
        output:
            'Deactivated package foo 1.0.0 from Git repository "../foo.git".');
  });
}
