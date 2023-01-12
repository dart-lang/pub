// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  forBothPubGetAndUpgrade((command) {
    test('fails gracefully if the package does not exist', () async {
      await servePackages();

      await d.appDir(dependencies: {'foo': '1.2.3'}).create();

      await pubCommand(
        command,
        error: allOf([
          contains(
              "Because myapp depends on foo any which doesn't exist (could "
              'not find package foo at http://localhost:'),
          contains('), version solving failed.')
        ]),
        exitCode: exit_codes.UNAVAILABLE,
      );
    });
  });

  forBothPubGetAndUpgrade((command) {
    test('fails gracefully if transitive dependencies does not exist',
        () async {
      final server = await servePackages();
      server.serve('foo', '1.2.3', deps: {'bar': '^1.0.0'});

      await d.appDir(dependencies: {'foo': '1.2.3'}).create();

      await pubCommand(
        command,
        error: allOf(
          contains('Because every version of foo depends on bar any which '
              'doesn\'t exist (could not find package bar at '
              'http://localhost:'),
          contains('), foo is forbidden.\n'
              'So, because myapp depends on foo 1.2.3, '
              'version solving failed.'),
        ),
        exitCode: exit_codes.UNAVAILABLE,
      );
    });
  });
}
