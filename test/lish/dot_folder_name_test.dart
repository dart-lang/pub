// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('Can publish files in a .folder', () async {
    await d.git(appPath).create();
    await d.validPackage().create();
    await d.dir(appPath, [
      d.dir('.vscode', [d.file('a')]),
      d.file('.pubignore', '!.vscode/')
    ]).create();
    await runPub(
      args: ['lish', '--dry-run'],
      output: contains('''
├── .vscode
│   └── a'''),
      exitCode: exit_codes.SUCCESS,
    );
  });
}
