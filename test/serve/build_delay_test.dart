// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:pub/src/io.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

main() {
  String libFilePath;

  setUp(() async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir("lib", [
        d.file("lib.dart", "foo() => 'foo';"),
      ])
    ]).create();

    await pubGet();
    libFilePath = p.join(d.sandbox, appPath, "lib", "lib.dart");
  });

  test("setting a long build-delay works", () async {
    var pubServeProcess =
        await pubServe(forcePoll: false, args: ['--build-delay', '1000']);
    expect(pubServeProcess.stdout,
        emitsThrough(contains('Build completed successfully')));
    await requestShouldSucceed("packages/myapp/lib.dart", "foo() => 'foo';");

    writeTextFile(libFilePath, "foo() => 'bar';");
    await new Future.delayed(new Duration(milliseconds: 500));
    writeTextFile(libFilePath, "foo() => 'baz';");

    // Should only see one build.
    expect(pubServeProcess.stdout,
        emitsThrough(contains('Build completed successfully')));
    expect(pubServeProcess.stdout, neverEmits('Build completed successfully'));

    await requestShouldSucceed("packages/myapp/lib.dart", "foo() => 'baz';");

    await endPubServe();
  });

  test("continual fast edits won't cause multiple builds", () async {
    // Set a larg-ish delay of 100ms to reduce flakyness on bots.
    var pubServeProcess =
        await pubServe(forcePoll: false, args: ['--build-delay', '100']);
    expect(pubServeProcess.stdout,
        emitsThrough(contains('Build completed successfully')));
    await requestShouldSucceed("packages/myapp/lib.dart", "foo() => 'foo';");

    for (var i = 0; i < 10; i++) {
      writeTextFile(libFilePath, "foo() => '$i';");
      // A 15ms delay is well under the 100ms limit set, but multiplied by 10 is
      // longer. This confirms that as long as edits continue happening the
      // build will remain paused, and should reduce bot flakyness.
      await new Future.delayed(new Duration(milliseconds: 15));
    }

    // Should only see one build.
    expect(pubServeProcess.stdout,
        emitsThrough(contains('Build completed successfully')));
    expect(pubServeProcess.stdout, neverEmits('Build completed successfully'));

    await requestShouldSucceed("packages/myapp/lib.dart", "foo() => '9';");

    await endPubServe();
  });

  // Regression test for https://github.com/dart-lang/sdk/issues/29890
  test("editors safe write features shouldn't cause failed builds", () async {
    // Increase default build delay to reduce flakyness on slow bots.
    var pubServeProcess =
        await pubServe(forcePoll: false, args: ['--build-delay', '250']);
    expect(pubServeProcess.stdout,
        emitsThrough(contains('Build completed successfully')));
    await requestShouldSucceed("packages/myapp/lib.dart", "foo() => 'foo';");

    // Simulate the safe-write feature from many editors:
    //   - Create a backup file
    //   - Edit original file
    //   - Delete backup file
    var backupFilePath = p.join(d.sandbox, appPath, "lib", "lib.dart.bak");
    writeTextFile(backupFilePath, "foo() => 'foo';");
    // Allow pub to schedule a new build.
    await new Future(() {});
    writeTextFile(libFilePath, "foo() => 'bar';");
    deleteEntry(backupFilePath);

    expect(pubServeProcess.stderr, neverEmits(contains("Build error")));
    expect(pubServeProcess.stdout,
        emitsThrough(contains('Build completed successfully')));
    await requestShould404("packages/myapp/lib.dart.bak");
    await requestShouldSucceed("packages/myapp/lib.dart", "foo() => 'bar';");

    await endPubServe();
  });
}
