// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

main() {
  test("preserves .htaccess as a special case", () async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir('web', [d.file('.htaccess', 'fblthp'), d.file('.hidden', 'asdfgh')])
    ]).create();

    await pubGet();
    await runPub(
        args: ["build"], output: new RegExp(r'Built \d+ files? to "build".'));

    await d.dir(appPath, [
      d.dir('build', [
        d.dir('web', [d.file('.htaccess', 'fblthp'), d.nothing('.hidden')])
      ])
    ]).validate();
  });
}
