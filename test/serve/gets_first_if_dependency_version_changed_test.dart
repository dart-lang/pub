// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

main() {
  test(
      "gets first if a dependency's version doesn't match the one in "
      "the lock file", () async {
    await d
        .dir("foo", [d.libPubspec("foo", "0.0.1"), d.libDir("foo")]).create();

    await d.appDir({
      "foo": {"path": "../foo", "version": "0.0.1"}
    }).create();

    await pubGet();

    // Change the version in the pubspec and package.
    await d.appDir({
      "foo": {"path": "../foo", "version": "0.0.2"}
    }).create();

    await d
        .dir("foo", [d.libPubspec("foo", "0.0.2"), d.libDir("foo")]).create();

    await pubGet();
    await pubServe();
    await requestShouldSucceed("packages/foo/foo.dart", 'main() => "foo";');
    await endPubServe();
  });
}
