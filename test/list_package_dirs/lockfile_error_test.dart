// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE d.file.

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:pub/src/io.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('reports the lockfile path when there is an error in it', () async {
    await d.dir(appPath,
        [d.appPubspec(), d.file('pubspec.lock', 'some bad yaml')]).create();

    await runPub(args: [
      'list-package-dirs',
      '--format=json'
    ], outputJson: {
      'error': contains('The lockfile must be a YAML mapping.'),
      'path': canonicalize(path.join(d.sandbox, appPath, 'pubspec.lock'))
    }, exitCode: exit_codes.DATA);
  });
}
