// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

main() {
  test("invalidates cache if asset changed", () async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir("web", [
        d.file("file.txt", "stuff"),
      ])
    ]).create();

    await pubGet();
    await pubServe();

    var response = await requestFromPub("file.txt");
    expect(response.statusCode, equals(200));
    expect(response.body, equals("stuff"));
    var etag = response.headers["etag"];

    await d.dir(appPath, [
      d.dir("web", [d.file("file.txt", "new stuff")])
    ]).create();

    await waitForBuildSuccess();

    response =
        await requestFromPub("file.txt", headers: {"if-none-match": etag});
    expect(response.statusCode, equals(200));
    expect(response.body, equals("new stuff"));

    await endPubServe();
  });
}
