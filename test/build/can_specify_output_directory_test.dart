// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

main() {
  test("can specify the output directory to build into", () async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir('web', [d.file('file.txt', 'web')])
    ]).create();

    await pubGet();
    var outDir = path.join("out", "dir");
    await runPub(
        args: ["build", "-o", outDir],
        output: contains('Built 1 file to "$outDir".'));

    await d.dir(appPath, [
      d.dir("out", [
        d.dir("dir", [
          d.dir("web", [d.file("file.txt", "web")]),
        ])
      ])
    ]).validate();
  });
}
