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
  forBothPubGetAndUpgrade((command) {
    test("implicitly constrains it to versions pub supports", () async {
      await servePackages((builder) {
        builder.serve("barback", current("barback"));
        builder.serve("stack_trace", previous("stack_trace"));
        builder.serve("stack_trace", current("stack_trace"));
        builder.serve("stack_trace", nextPatch("stack_trace"));
        builder.serve("stack_trace", max("stack_trace"));
        builder.serve("source_span", current("source_span"));
        builder.serve("async", current("async"));
      });

      await d.appDir({"barback": "any"}).create();

      await pubCommand(command);

      await d.appPackagesFile({
        "async": current("async"),
        "barback": current("barback"),
        "source_span": current("source_span"),
        "stack_trace": nextPatch("stack_trace")
      }).validate();
    });

    test(
        "pub's implicit constraint uses the same source and "
        "description as a dependency override", () async {
      await servePackages((builder) {
        builder.serve("barback", current("barback"));
        builder.serve("stack_trace", nextPatch("stack_trace"));
        builder.serve("source_span", current("source_span"));
        builder.serve("async", current("async"));
      });

      await d.dir("stack_trace", [
        d.libDir("stack_trace", 'stack_trace ${current("stack_trace")}'),
        d.libPubspec("stack_trace", current("stack_trace"))
      ]).create();

      await d.dir(appPath, [
        d.pubspec({
          "name": "myapp",
          "dependencies": {"barback": "any"},
          "dependency_overrides": {
            "stack_trace": {"path": "../stack_trace"},
          }
        })
      ]).create();

      await pubCommand(command);
      // Validate that we're using the path dependency version of stack_trace
      // rather than the hosted version.

      await d.appPackagesFile({
        "async": current("async"),
        "barback": current("barback"),
        "source_span": current("source_span"),
        "stack_trace": "../stack_trace"
      }).validate();
    });

    test(
        "doesn't add a constraint if barback isn't in the package "
        "graph", () async {
      await servePackages((builder) {
        builder.serve("stack_trace", previous("stack_trace"));
        builder.serve("stack_trace", current("stack_trace"));
        builder.serve("stack_trace", nextPatch("stack_trace"));
        builder.serve("stack_trace", max("stack_trace"));
        builder.serve("source_span", current("source_span"));
        builder.serve("async", current("async"));
      });

      await d.appDir({"stack_trace": "any"}).create();

      await pubCommand(command);

      await d.appPackagesFile({"stack_trace": max("stack_trace")}).validate();
    });
  });

  test(
      "unlocks if the locked version doesn't meet pub's "
      "constraint", () async {
    await servePackages((builder) {
      builder.serve("barback", current("barback"));
      builder.serve("stack_trace", previous("stack_trace"));
      builder.serve("stack_trace", current("stack_trace"));
      builder.serve("source_span", current("source_span"));
      builder.serve("async", current("async"));
    });

    await d.appDir({"barback": "any"}).create();
    // Hand-create a lockfile to pin the package to an older version.

    await createLockFile("myapp", hosted: {
      "barback": current("barback"),
      "stack_trace": previous("stack_trace")
    });

    await pubGet();
    // It should be upgraded.

    await d.appPackagesFile({
      "async": current("async"),
      "barback": current("barback"),
      "source_span": current("source_span"),
      "stack_trace": current("stack_trace")
    }).validate();
  });
}

String current(String packageName) =>
    barback.pubConstraints[packageName].min.toString();

String previous(String packageName) {
  var constraint = barback.pubConstraints[packageName];
  return new Version(constraint.min.major, constraint.min.minor - 1, 0)
      .toString();
}

String nextPatch(String packageName) =>
    barback.pubConstraints[packageName].min.nextPatch.toString();

String max(String packageName) =>
    barback.pubConstraints[packageName].max.toString();
