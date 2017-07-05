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

  test("setting build-delay to zero causes a build per edit", () async {
    var pubServeProcess =
        await pubServe(forcePoll: false, args: ['--build-delay', '0']);
    expect(pubServeProcess.stdout,
        emitsThrough(contains('Build completed successfully')));
    await requestShouldSucceed("packages/myapp/lib.dart", "foo() => 'foo';");

    // Flush here as that helps to make sure we get multiple modify events,
    // otherwise we tend to only get one.
    writeTextFile(libFilePath, "foo() => 'bar';");
    await new Future(() {});
    writeTextFile(libFilePath, "foo() => 'baz';");

    // Should see multiple builds.
    expect(pubServeProcess.stdout,
        emitsThrough(contains('Build completed successfully')));
    expect(pubServeProcess.stdout,
        emitsThrough(contains('Build completed successfully')));

    await requestShouldSucceed("packages/myapp/lib.dart", "foo() => 'baz';");

    await endPubServe();
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
    var pubServeProcess =
        await pubServe(forcePoll: false, args: ['--build-delay', '100']);
    expect(pubServeProcess.stdout,
        emitsThrough(contains('Build completed successfully')));
    await requestShouldSucceed("packages/myapp/lib.dart", "foo() => 'foo';");

    for (var i = 0; i < 10; i++) {
      writeTextFile(libFilePath, "foo() => '$i';");
      await new Future.delayed(new Duration(milliseconds: 50));
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
    var pubServeProcess = await pubServe(forcePoll: false);
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
