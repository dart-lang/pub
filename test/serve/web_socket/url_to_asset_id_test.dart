// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';
import '../utils.dart';

main() {
  setUp(() async {
    await d.dir("foo", [
      d.libPubspec("foo", "0.0.1"),
      d.dir("lib", [d.file("foo.dart", "foo")])
    ]).create();

    await d.dir(appPath, [
      d.appPubspec({
        "foo": {"path": "../foo"}
      }),
      d.dir("lib", [
        d.file("myapp.dart", "myapp"),
      ]),
      d.dir("test", [
        d.file("index.html", "<body>"),
        d.dir("sub", [
          d.file("bar.html", "bar"),
        ])
      ]),
      d.dir("web", [
        d.file("index.html", "<body>"),
        d.dir("sub", [
          d.file("bar.html", "bar"),
        ])
      ])
    ]).create();

    await pubGet();
  });

  test("converts URLs to matching asset ids in web/", () async {
    await pubServe();
    await expectWebSocketResult(
        "urlToAssetId",
        {"url": getServerUrl("web", "index.html")},
        {"package": "myapp", "path": "web/index.html"});
    await endPubServe();
  });

  test("converts URLs to matching asset ids in subdirectories of web/",
      () async {
    await pubServe();
    await expectWebSocketResult(
        "urlToAssetId",
        {"url": getServerUrl("web", "sub/bar.html")},
        {"package": "myapp", "path": "web/sub/bar.html"});
    await endPubServe();
  });

  test("converts URLs to matching asset ids in test/", () async {
    await pubServe();
    await expectWebSocketResult(
        "urlToAssetId",
        {"url": getServerUrl("test", "index.html")},
        {"package": "myapp", "path": "test/index.html"});
    await endPubServe();
  });

  test("converts URLs to matching asset ids in subdirectories of test/",
      () async {
    await pubServe();
    await expectWebSocketResult(
        "urlToAssetId",
        {"url": getServerUrl("test", "sub/bar.html")},
        {"package": "myapp", "path": "test/sub/bar.html"});
    await endPubServe();
  });

  test("converts URLs to matching asset ids in the entrypoint's lib/",
      () async {
    // Path in root package's lib/.
    await pubServe();
    await expectWebSocketResult(
        "urlToAssetId",
        {"url": getServerUrl("web", "packages/myapp/myapp.dart")},
        {"package": "myapp", "path": "lib/myapp.dart"});
    await endPubServe();
  });

  test("converts URLs to matching asset ids in a dependency's lib/", () async {
    // Path in lib/.
    await pubServe();
    await expectWebSocketResult(
        "urlToAssetId",
        {"url": getServerUrl("web", "packages/foo/foo.dart")},
        {"package": "foo", "path": "lib/foo.dart"});
    await endPubServe();
  });
}
