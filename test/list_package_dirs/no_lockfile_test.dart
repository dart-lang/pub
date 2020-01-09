// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE d.file.

import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('with no lockfile, exits with error', () async {
    await d.dir(appPath, [d.appPubspec()]).create();

    await runPub(args: [
      'list-package-dirs',
      '--format=json'
    ], outputJson: {
      'error': 'Package "myapp" has no lockfile. Please run "pub get" first.'
    }, exitCode: exit_codes.DATA);
  });
}
