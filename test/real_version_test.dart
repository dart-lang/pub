// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:pub/src/sdk.dart';

void main() {
  // This test is a bit funny.
  //
  // Pub parses the "version" file that gets generated and shipped with the SDK.
  // We want to make sure that the actual version file that gets created is
  // also one pub can parse. If this test fails, it means the version file's
  // format has changed in a way pub didn't expect.
  //
  // Note that this test expects to be invoked from a Dart executable that is
  // in the built SDK's "bin" directory. Note also that this invokes pub from
  // the built SDK directory, and not the live pub code directly in the repo.
  test('parse the real SDK "version" file', () async {
    // Get the path to the pub binary in the SDK.
    var pubPath = path.join(
        sdk.rootDirectory, 'bin', Platform.isWindows ? 'pub.bat' : 'pub');

    var pub = await TestProcess.start(pubPath, ['version']);
    expect(pub.stdout, emits(startsWith('Pub')));
    await pub.shouldExit(exit_codes.SUCCESS);
  });
}
