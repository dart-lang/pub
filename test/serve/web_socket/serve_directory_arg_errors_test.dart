// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:json_rpc_2/error_code.dart' as rpc_error_code;
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';
import '../utils.dart';

main() {
  setUp(() async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir("web", [d.file("index.html", "<body>")])
    ]).create();
    await pubGet();
  });

  test("responds with an error if 'path' is not a string", () async {
    await pubServe();
    await expectWebSocketError(
        "serveDirectory",
        {"path": 123},
        rpc_error_code.INVALID_PARAMS,
        'Parameter "path" for method "serveDirectory" must be a string, but '
        'was 123.');
    await endPubServe();
  });

  test("responds with an error if 'path' is absolute", () async {
    await pubServe();
    await expectWebSocketError(
        "serveDirectory",
        {"path": "/absolute.txt"},
        rpc_error_code.INVALID_PARAMS,
        '"path" must be a relative path. Got "/absolute.txt".');
    await endPubServe();
  });

  test("responds with an error if 'path' reaches out", () async {
    await pubServe();
    await expectWebSocketError(
        "serveDirectory",
        {"path": "a/../../bad.txt"},
        rpc_error_code.INVALID_PARAMS,
        '"path" cannot reach out of its containing directory. Got '
        '"a/../../bad.txt".');
    await endPubServe();
  });
}
