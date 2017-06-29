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
  File libFile;

  setUp(() async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir("lib", [
        d.file("lib.dart", "foo() => 'foo';"),
      ])
    ]).create();

    await pubGet();
    libFile = new File(p.join(d.sandbox, appPath, "lib", "lib.dart"));
  });

  test("setting build-delay to zero causes a build per edit", () async {
    var pubServeProcess =
        await pubServe(forcePoll: false, args: ['--build-delay', '0']);
    expect(pubServeProcess.stdout,
        emitsThrough(contains('Build completed successfully')));
    await requestShouldSucceed("packages/myapp/lib.dart", "foo() => 'foo';");

    // Flush here as that helps to make sure we get multiple modify events,
    // otherwise we tend to only get one.
    libFile.writeAsStringSync("foo() => 'bar';", flush: true);
    libFile.writeAsStringSync("foo() => 'baz';", flush: true);

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

    await libFile.writeAsString("foo() => 'bar';");
    await new Future.delayed(new Duration(milliseconds: 500));
    await libFile.writeAsString("foo() => 'baz';");

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
      await libFile.writeAsString("foo() => '$i';");
      await new Future.delayed(new Duration(milliseconds: 50));
    }

    // Should only see one build.
    expect(pubServeProcess.stdout,
        emitsThrough(contains('Build completed successfully')));
    expect(pubServeProcess.stdout, neverEmits('Build completed successfully'));

    await requestShouldSucceed("packages/myapp/lib.dart", "foo() => '9';");

    await endPubServe();
  });
}
