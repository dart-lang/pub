// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:scheduled_test/scheduled_test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

main() {
  integration("invalidates cache if asset changed", () {
    d.dir(appPath, [
      d.appPubspec(),
      d.dir("web", [
        d.file("file.txt", "stuff"),
      ])
    ]).create();

    pubGet();
    pubServe();

    String etag;
    schedule(() async {
      var response = await scheduleRequest("file.txt");
      expect(response.statusCode, equals(200));
      expect(response.body, equals("stuff"));
      etag = response.headers["etag"];
    });

    d.dir(appPath, [
      d.dir("web", [
        d.file("file.txt", "new stuff")
      ])
    ]).create();

    waitForBuildSuccess();

    schedule(() async {
      var response = await scheduleRequest("file.txt",
          headers: {"if-none-match": etag});
      expect(response.statusCode, equals(200));
      expect(response.body, equals("new stuff"));
    });

    endPubServe();
  });
}
