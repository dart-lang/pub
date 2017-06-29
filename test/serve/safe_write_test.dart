// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

main() {
  // Regression test for https://github.com/dart-lang/sdk/issues/29890
  test("editors safe write features shouldn't cause failed builds", () async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir("lib", [
        d.file("lib.dart", "foo() => 'foo';"),
      ])
    ]).create();

    await pubGet();
    var pubServeProcess = await pubServe(forcePoll: false);
    expect(pubServeProcess.stdout,
        emitsThrough(contains('Build completed successfully')));
    await requestShouldSucceed("packages/myapp/lib.dart", "foo() => 'foo';");

    // Simulate the safe-write feature from many editors:
    //   - Create a backup file
    //   - Edit original file
    //   - Delete backup file
    var backupFile =
        new File(p.join(d.sandbox, appPath, "lib", "lib.dart.bak"));
    backupFile.createSync();
    // Allow pub to schedule a new build.
    await new Future(() {});
    var originalFile = new File(p.join(d.sandbox, appPath, "lib", "lib.dart"));
    originalFile.writeAsStringSync("foo() => 'bar';");
    backupFile.deleteSync();

    expect(pubServeProcess.stderr, neverEmits(contains("Build error")));
    expect(pubServeProcess.stdout,
        emitsThrough(contains('Build completed successfully')));
    await requestShould404("packages/myapp/lib.dart.bak");
    await requestShouldSucceed("packages/myapp/lib.dart", "foo() => 'bar';");

    await endPubServe();
  });
}
