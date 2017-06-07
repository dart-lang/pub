// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';
import '../utils.dart';

main() {
  setUp(() async {
    await d.dir(appPath, [d.appPubspec()]).create();
    await pubGet();
  });

  test("responds with NOT_SERVED for an unknown domain", () async {
    await pubServe();
    await expectWebSocketError(
        "urlToAssetId",
        {"url": "http://example.com:80/index.html"},
        NOT_SERVED,
        '"example.com:80" is not being served by pub.');
    await endPubServe();
  });

  test("responds with NOT_SERVED for an unknown port", () async {
    await pubServe();
    await expectWebSocketError(
        "urlToAssetId",
        {"url": "http://localhost:80/index.html"},
        NOT_SERVED,
        '"localhost:80" is not being served by pub.');
    await endPubServe();
  });
}
