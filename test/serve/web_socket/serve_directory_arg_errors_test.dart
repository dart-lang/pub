// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:json_rpc_2/error_code.dart' as rpc_error_code;
import 'package:scheduled_test/scheduled_test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';
import '../utils.dart';

main() {
  setUp(() {
    d.dir(appPath, [
      d.appPubspec(),
      d.dir("web", [d.file("index.html", "<body>")])
    ]).create();
    pubGet();
  });

  integration("responds with an error if 'path' is not a string", () {
    pubServe();
    expectWebSocketError(
        "serveDirectory",
        {"path": 123},
        rpc_error_code.INVALID_PARAMS,
        'Parameter "path" for method "serveDirectory" must be a string, but '
        'was 123.');
    endPubServe();
  });

  integration("responds with an error if 'path' is absolute", () {
    pubServe();
    expectWebSocketError(
        "serveDirectory",
        {"path": "/absolute.txt"},
        rpc_error_code.INVALID_PARAMS,
        '"path" must be a relative path. Got "/absolute.txt".');
    endPubServe();
  });

  integration("responds with an error if 'path' reaches out", () {
    pubServe();
    expectWebSocketError(
        "serveDirectory",
        {"path": "a/../../bad.txt"},
        rpc_error_code.INVALID_PARAMS,
        '"path" cannot reach out of its containing directory. Got '
        '"a/../../bad.txt".');
    endPubServe();
  });
}
