// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Skip()

import 'package:test/test.dart';

import 'package:pub/src/barback.dart' as barback;
import 'package:pub_semver/pub_semver.dart';

import 'descriptor.dart' as d;
import 'test_pub.dart';

main() {
  var constraint = barback.pubConstraints["barback"];
  var current = constraint.min.toString();
  var previous =
      new Version(constraint.min.major, constraint.min.minor - 1, 0).toString();
  var nextPatch = constraint.min.nextPatch.toString();
  var max = constraint.max.toString();

  var sourceSpanVersion = barback.pubConstraints["source_span"].min.toString();
  var stackTraceVersion = barback.pubConstraints["stack_trace"].min.toString();
  var asyncVersion = barback.pubConstraints["async"].min.toString();

  forBothPubGetAndUpgrade((command) {
    test("implicitly constrains barback to versions pub supports", () async {
      await servePackages((builder) {
        builder.serve("barback", previous);
        builder.serve("barback", current);
        builder.serve("barback", nextPatch);
        builder.serve("barback", max);
        builder.serve("source_span", sourceSpanVersion);
        builder.serve("stack_trace", stackTraceVersion);
        builder.serve("async", asyncVersion);
      });

      await d.appDir({"barback": "any"}).create();

      await pubCommand(command);

      await d.appPackagesFile({
        "async": asyncVersion,
        "barback": nextPatch,
        "source_span": sourceSpanVersion,
        "stack_trace": stackTraceVersion
      }).validate();
    });

    test("discovers transitive dependency on barback", () async {
      await servePackages((builder) {
        builder.serve("barback", previous);
        builder.serve("barback", current);
        builder.serve("barback", nextPatch);
        builder.serve("barback", max);
        builder.serve("source_span", sourceSpanVersion);
        builder.serve("stack_trace", stackTraceVersion);
        builder.serve("async", asyncVersion);
      });

      await d.dir("foo", [
        d.libDir("foo", "foo 0.0.1"),
        d.libPubspec("foo", "0.0.1", deps: {"barback": "any"})
      ]).create();

      await d.appDir({
        "foo": {"path": "../foo"}
      }).create();

      await pubCommand(command);

      await d.appPackagesFile({
        "async": asyncVersion,
        "barback": nextPatch,
        "source_span": sourceSpanVersion,
        "stack_trace": stackTraceVersion,
        "foo": "../foo"
      }).validate();
    });

    test(
        "pub's implicit constraint uses the same source and "
        "description as a dependency override", () async {
      await servePackages((builder) {
        builder.serve("source_span", sourceSpanVersion);
        builder.serve("stack_trace", stackTraceVersion);
        builder.serve("async", asyncVersion);
      });

      await d.dir('barback', [
        d.libDir('barback', 'barback $current'),
        d.libPubspec('barback', current),
      ]).create();

      await d.dir(appPath, [
        d.pubspec({
          "name": "myapp",
          "dependency_overrides": {
            "barback": {"path": "../barback"}
          }
        })
      ]).create();

      await pubCommand(command);

      await d.appPackagesFile({
        "async": asyncVersion,
        "barback": "../barback",
        "source_span": sourceSpanVersion,
        "stack_trace": stackTraceVersion,
      }).validate();
    });
  });

  test("unlock if the locked version doesn't meet pub's constraint", () async {
    await servePackages((builder) {
      builder.serve("barback", previous);
      builder.serve("barback", current);
      builder.serve("source_span", sourceSpanVersion);
      builder.serve("stack_trace", stackTraceVersion);
      builder.serve("async", asyncVersion);
    });

    await d.appDir({"barback": "any"}).create();
    // Hand-create a lockfile to pin barback to an older version.

    await createLockFile("myapp", hosted: {"barback": previous});

    await pubGet();
    // It should be upgraded.

    await d.appPackagesFile({
      "async": asyncVersion,
      "barback": current,
      "source_span": sourceSpanVersion,
      "stack_trace": stackTraceVersion,
    }).validate();
  });

  test(
      "includes pub in the error if a solve failed because there "
      "is no version available", () async {
    await servePackages((builder) {
      builder.serve("barback", previous);
      builder.serve("source_span", sourceSpanVersion);
      builder.serve("stack_trace", stackTraceVersion);
      builder.serve("async", asyncVersion);
    });

    await d.appDir({"barback": "any"}).create();

    await pubGet(error: """
Package barback has no versions that match >=$current <$max derived from:
- myapp depends on version any
- pub itself depends on version >=$current <$max""");
  });

  test(
      "includes pub in the error if a solve failed because there "
      "is a disjoint constraint", () async {
    await servePackages((builder) {
      builder.serve("barback", previous);
      builder.serve("barback", current);
      builder.serve("source_span", sourceSpanVersion);
      builder.serve("stack_trace", stackTraceVersion);
      builder.serve("async", asyncVersion);
    });

    await d.appDir({"barback": previous}).create();

    await pubGet(error: """
Incompatible version constraints on barback:
- myapp depends on version $previous
- pub itself depends on version >=$current <$max""");
  });
}
