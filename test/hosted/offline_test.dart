// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../descriptor.dart' as d;
import '../test_pub.dart';

main() {
  forBothPubGetAndUpgrade((command) {
    integration('upgrades a package using the cache', () {
      // Run the server so that we know what URL to use in the system cache.
      serveErrors();

      d.cacheDir({
        "foo": ["1.2.2", "1.2.3"],
        "bar": ["1.2.3"]
      }, includePubspecs: true).create();

      d.appDir({
        "foo": "any",
        "bar": "any"
      }).create();

      var warning = null;
      if (command == RunCommand.upgrade) {
        warning = "Warning: Upgrading when offline may not update you "
                  "to the latest versions of your dependencies.";
      }

      pubCommand(command, args: ['--offline'], warning: warning);

      d.packagesDir({
        "foo": "1.2.3",
        "bar": "1.2.3"
      }).validate();
    });

    integration('fails gracefully if a dependency is not cached', () {
      // Run the server so that we know what URL to use in the system cache.
      serveErrors();

      d.appDir({"foo": "any"}).create();

      pubCommand(command, args: ['--offline'],
          exitCode: exit_codes.UNAVAILABLE,
          error: "Could not find package foo in cache.\n"
                 "Depended on by:\n"
                 "- myapp");
    });

    integration('fails gracefully if no cached versions match', () {
      // Run the server so that we know what URL to use in the system cache.
      serveErrors();

      d.cacheDir({
        "foo": ["1.2.2", "1.2.3"]
      }, includePubspecs: true).create();

      d.appDir({"foo": ">2.0.0"}).create();

      pubCommand(command, args: ['--offline'], error:
          "Package foo has no versions that match >2.0.0 derived from:\n"
          "- myapp depends on version >2.0.0");
    });

    integration('fails gracefully if a dependency is not cached and a lockfile '
        'exists', () {
      // Run the server so that we know what URL to use in the system cache.
      serveErrors();

      d.appDir({"foo": "any"}).create();

      createLockFile('myapp', hosted: {'foo': '1.2.4'});

      pubCommand(command, args: ['--offline'],
          exitCode: exit_codes.UNAVAILABLE,
          error: "Could not find package foo in cache.\n"
                 "Depended on by:\n"
                 "- myapp");
    });

    integration('downgrades to the version in the cache if necessary', () {
      // Run the server so that we know what URL to use in the system cache.
      serveErrors();

      d.cacheDir({
        "foo": ["1.2.2", "1.2.3"]
      }, includePubspecs: true).create();

      d.appDir({"foo": "any"}).create();

      createLockFile('myapp', hosted: {'foo': '1.2.4'});

      pubCommand(command, args: ['--offline']);

      d.packagesDir({"foo": "1.2.3"}).validate();
    });
  });
}
