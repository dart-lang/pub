// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:pub/src/io.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('errors if the local package does not exist', () async {
    await d.dir('foo', [
      d.libPubspec('foo', '1.0.0'),
      d.dir('bin', [d.file('foo.dart', "main() => print('ok');")])
    ]).create();

    await runPub(args: ['global', 'activate', '--source', 'path', '../foo']);

    deleteEntry(p.join(d.sandbox, 'foo'));

    var pub = await pubRun(global: true, args: ['foo']);
    var path = canonicalize(p.join(d.sandbox, 'foo'));
    expect(pub.stderr,
        emits('Could not find a file named "pubspec.yaml" in "$path".'));
    await pub.shouldExit(exit_codes.NO_INPUT);
  });
}
