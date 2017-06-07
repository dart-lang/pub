// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:test/test.dart';

import 'package:json_rpc_2/error_code.dart' as rpc_error_code;
import 'package:path/path.dart' as p;

import '../../descriptor.dart' as d;
import '../../test_pub.dart';
import '../utils.dart';

main() {
  // TODO(rnystrom): Split into independent tests.
  test("pathToUrls errors on bad inputs", () async {
    await d.dir("foo", [
      d.libPubspec("foo", "1.0.0"),
      d.dir("web", [d.file("foo.txt", "foo")])
    ]).create();

    await d.dir(appPath, [
      d.appPubspec({
        "foo": {"path": "../foo"}
      }),
      d.file("top-level.txt", "top-level"),
      d.dir("bin", [
        d.file("foo.txt", "foo"),
      ]),
      d.dir("lib", [
        d.file("myapp.dart", "myapp"),
      ])
    ]).create();

    await pubGet();
    await pubServe();

    // Bad arguments.
    await expectWebSocketError(
        "pathToUrls",
        {"path": 123},
        rpc_error_code.INVALID_PARAMS,
        'Parameter "path" for method "pathToUrls" must be a string, but was '
        '123.');

    await expectWebSocketError(
        "pathToUrls",
        {"path": "main.dart", "line": 12.34},
        rpc_error_code.INVALID_PARAMS,
        'Parameter "line" for method "pathToUrls" must be an integer, but was '
        '12.34.');

    // Unserved directories.
    await expectNotServed(p.join('bin', 'foo.txt'));
    await expectNotServed(p.join('nope', 'foo.txt'));
    await expectNotServed(p.join("..", "bar", "lib", "bar.txt"));
    await expectNotServed(p.join("..", "foo", "web", "foo.txt"));

    await endPubServe();
  });
}

Future expectNotServed(String path) {
  return expectWebSocketError("pathToUrls", {"path": path}, NOT_SERVED,
      'Asset path "$path" is not currently being served.');
}
