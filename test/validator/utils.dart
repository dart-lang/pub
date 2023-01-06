// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:test/test.dart';

import '../test_pub.dart';

// TODO(sigurdm) consider rewriting all validator tests as integration tests.
// That would make them more robust, and test actual end2end behaviour.

Future<void> expectValidation(ValidatorCreator fn,
    {hints, warnings, errors, int? size}) async {
  final validator = await validatePackage(fn, size);
  expect(validator.errors, errors ?? isEmpty);
  expect(validator.warnings, warnings ?? isEmpty);
  expect(validator.hints, hints ?? isEmpty);
}

// On windows symlinks to directories are distinct from symlinks to files.
void createDirectorySymlink(String path, String target) {
  if (Platform.isWindows) {
    Process.runSync('cmd', ['/c', 'mklink', '/D', path, target]);
  } else {
    Link(path).createSync(target);
  }
}
