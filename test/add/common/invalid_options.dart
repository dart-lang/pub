// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('cannot use both --path and --git-url flags', () async {
    ensureGit();

    await d.git(
        'foo.git', [d.libDir('foo'), d.libPubspec('foo', '1.0.0')]).create();
    await d
        .dir('bar', [d.libDir('bar'), d.libPubspec('foo', '0.0.1')]).create();

    await d.appDir({}).create();

    await pubAdd(
        args: ['foo', '--git-url', '../foo.git', '--path', '../bar'],
        error: contains('Cannot pass both path and a git option.'),
        exitCode: exit_codes.USAGE);
  });
}
