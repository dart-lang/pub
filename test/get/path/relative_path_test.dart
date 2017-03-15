// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE d.file.

import 'package:path/path.dart' as path;
import 'package:pub/src/lock_file.dart';
import 'package:pub/src/source_registry.dart';
import 'package:scheduled_test/scheduled_test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

main() {
  integration("can use relative path", () {
    d.dir("foo", [d.libDir("foo"), d.libPubspec("foo", "0.0.1")]).create();

    d.dir(appPath, [
      d.appPubspec({
        "foo": {"path": "../foo"}
      })
    ]).create();

    pubGet();

    d.appPackagesFile({"foo": "../foo"}).validate();
  });

  integration("path is relative to containing pubspec", () {
    d.dir("relative", [
      d.dir("foo", [
        d.libDir("foo"),
        d.libPubspec("foo", "0.0.1", deps: {
          "bar": {"path": "../bar"}
        })
      ]),
      d.dir("bar", [d.libDir("bar"), d.libPubspec("bar", "0.0.1")])
    ]).create();

    d.dir(appPath, [
      d.appPubspec({
        "foo": {"path": "../relative/foo"}
      })
    ]).create();

    pubGet();

    d.appPackagesFile(
        {"foo": "../relative/foo", "bar": "../relative/bar"}).validate();
  });

  integration("relative path preserved in the lockfile", () {
    d.dir("foo", [d.libDir("foo"), d.libPubspec("foo", "0.0.1")]).create();

    d.dir(appPath, [
      d.appPubspec({
        "foo": {"path": "../foo"}
      })
    ]).create();

    pubGet();

    schedule(() {
      var lockfilePath = path.join(sandboxDir, appPath, "pubspec.lock");
      var lockfile = new LockFile.load(lockfilePath, new SourceRegistry());
      var description = lockfile.packages["foo"].description;

      expect(path.isRelative(description["path"]), isTrue);
    });
  });
}
