// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:scheduled_test/scheduled_test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

main() {
  forBothPubGetAndUpgrade((command) {
    integration('sends metadata headers for a direct dependency', () {
      servePackages((builder) {
        builder.serve("foo", "1.0.0");
      });

      d.appDir({"foo": "1.0.0"}).create();

      pubCommand(command,
          silent: allOf([
            contains("X-Pub-OS: ${Platform.operatingSystem}"),
            contains("X-Pub-Command: ${command.name}"),
            contains("X-Pub-Session-ID:"),
            isNot(contains("X-Pub-Environment")),
            contains("X-Pub-Reason: direct"),
            isNot(contains("X-Pub-Reason: dev")),
          ]));
    });

    integration('sends metadata headers for a dev dependency', () {
      servePackages((builder) {
        builder.serve("foo", "1.0.0");
      });

      d.dir(appPath, [
        d.pubspec({
          "name": "myapp",
          "dev_dependencies": {"foo": "1.0.0"}
        })
      ]).create();

      pubCommand(command,
          silent: allOf([
            contains("X-Pub-OS: ${Platform.operatingSystem}"),
            contains("X-Pub-Command: ${command.name}"),
            contains("X-Pub-Session-ID:"),
            isNot(contains("X-Pub-Environment")),
            contains("X-Pub-Reason: dev"),
            isNot(contains("X-Pub-Reason: direct")),
          ]));
    });

    integration('sends metadata headers for a transitive dependency', () {
      servePackages((builder) {
        builder.serve("bar", "1.0.0");
      });

      d.appDir({
        "foo": {"path": "../foo"}
      }).create();

      d.dir("foo", [
        d.libPubspec("foo", "1.0.0", deps: {"bar": "1.0.0"})
      ]).create();

      pubCommand(command,
          silent: allOf([
            contains("X-Pub-OS: ${Platform.operatingSystem}"),
            contains("X-Pub-Command: ${command.name}"),
            contains("X-Pub-Session-ID:"),
            isNot(contains("X-Pub-Environment")),
            isNot(contains("X-Pub-Reason:")),
          ]));
    });

    integration("doesn't send metadata headers to a foreign server", () {
      var server = new PackageServer((builder) {
        builder.serve("foo", "1.0.0");
      });

      d.appDir({
        "foo": {
          "version": "1.0.0",
          "hosted": {
            "name": "foo",
            "url": server.port.then((port) => "http://localhost:$port")
          }
        }
      }).create();

      pubCommand(command, silent: isNot(contains("X-Pub-")));
    });
  });
}
