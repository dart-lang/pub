// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:scheduled_test/scheduled_test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

main() {
  setUp(() {
    d.dir(appPath, [d.appPubspec()]).create();
  });

  integration("the 404 page describes the missing asset", () {
    pubGet();
    pubServe();

    scheduleRequest("packages/foo/missing.txt").then((response) {
      expect(response.statusCode, equals(404));

      // Should mention the asset that can't be found.
      expect(response.body, contains("foo"));
      expect(response.body, contains("missing.txt"));
    });

    endPubServe();
  });

  integration("the 404 page describes the error", () {
    pubGet();
    pubServe();

    scheduleRequest("packages").then((response) {
      expect(response.statusCode, equals(404));

      // Should mention the asset that can't be found.
      expect(response.body, contains('&quot;packages&quot;'));
    });

    endPubServe();
  });
}
