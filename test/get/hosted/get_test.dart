// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

main() {
  integration('gets a package from a pub server', () {
    servePackages((builder) => builder.serve("foo", "1.2.3"));

    d.appDir({"foo": "1.2.3"}).create();

    pubGet();

    d.cacheDir({"foo": "1.2.3"}).validate();
    d.appPackagesFile({"foo": "1.2.3"}).validate();
  });

  integration('URL encodes the package name', () {
    serveNoPackages();

    d.appDir({"bad name!": "1.2.3"}).create();

    pubGet(
        error: new RegExp(
          r"Could not find package bad name! at http://localhost:\d+\."),
        exitCode: exit_codes.UNAVAILABLE);
  });

  integration('gets a package from a non-default pub server', () {
    // Make the default server serve errors. Only the custom server should
    // be accessed.
    serveErrors();

    var server = new PackageServer((builder) {
      builder.serve("foo", "1.2.3");
    });

    d.appDir({
      "foo": {
        "version": "1.2.3",
        "hosted": {
          "name": "foo",
          "url": server.port.then((port) => "http://localhost:$port")
        }
      }
    }).create();

    pubGet();

    d.cacheDir({"foo": "1.2.3"}, port: server.port).validate();
    d.appPackagesFile({"foo": "1.2.3"}).validate();
  });
}
