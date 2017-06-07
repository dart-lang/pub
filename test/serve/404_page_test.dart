// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

main() {
  setUp(() => d.dir(appPath, [d.appPubspec()]).create());

  test("the 404 page describes the missing asset", () async {
    await pubGet();
    await pubServe();

    var response = await requestFromPub("packages/foo/missing.txt");
    expect(response.statusCode, equals(404));

    // Should mention the asset that can't be found.
    expect(response.body, contains("foo"));
    expect(response.body, contains("missing.txt"));

    await endPubServe();
  });

  test("the 404 page describes the error", () async {
    await pubGet();
    await pubServe();

    var response = await requestFromPub("packages");
    expect(response.statusCode, equals(404));

    // Should mention the asset that can't be found.
    expect(response.body, contains('&quot;packages&quot;'));

    await endPubServe();
  });
}
