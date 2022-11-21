// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../../test_pub.dart';

void main() {
  test('fails if the Git repo does not exist', () async {
    ensureGit();

    await runPub(
      args: ['global', 'activate', '-sgit', '../nope.git'],
      error: contains("/nope.git' does not appear to be a git repository"),
      exitCode: exit_codes.UNAVAILABLE,
    );
  });
}
