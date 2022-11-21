// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../../descriptor.dart';
import '../../test_pub.dart';

void main() {
  test('fails if the Git repo does not exist', () async {
    ensureGit();

    // Git will report the error message using forward slashes, even on Windows.
    final pathWithSlashes = p.posix.joinAll([...p.split(sandbox), 'nope.git']);

    await runPub(
      args: ['global', 'activate', '-sgit', '../nope.git'],
      error: contains(
        "'$pathWithSlashes' does not appear to be a git repository",
      ),
      exitCode: exit_codes.UNAVAILABLE,
    );
  });
}
