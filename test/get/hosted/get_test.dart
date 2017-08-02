// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

main() {
  test('gets a package from a pub server', () async {
    await servePackages((builder) => builder.serve("foo", "1.2.3"));

    await d.appDir({"foo": "1.2.3"}).create();

    await pubGet();

    await d.cacheDir({"foo": "1.2.3"}).validate();
    await d.appPackagesFile({"foo": "1.2.3"}).validate();
  });

  test('URL encodes the package name', () async {
    await serveNoPackages();

    await d.appDir({"bad name!": "1.2.3"}).create();

    await pubGet(
        error: new RegExp(
            r"Could not find package bad name! at http://localhost:\d+\."),
        exitCode: exit_codes.UNAVAILABLE);
  });

  test('gets a package from a non-default pub server', () async {
    // Make the default server serve errors. Only the custom server should
    // be accessed.
    await serveErrors();

    var server = await PackageServer.start((builder) {
      builder.serve("foo", "1.2.3");
    });

    await d.appDir({
      "foo": {
        "version": "1.2.3",
        "hosted": {"name": "foo", "url": "http://localhost:${server.port}"}
      }
    }).create();

    await pubGet();

    await d.cacheDir({"foo": "1.2.3"}, port: server.port).validate();
    await d.appPackagesFile({"foo": "1.2.3"}).validate();
  });
}
