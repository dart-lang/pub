// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart=2.10

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('allows a third party tool to resolve dependencies', () async {
    await d.dir('local_baz', [
      d.pubspec({'name': 'baz'}),
    ]).create();

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependencies': {
          // Path dependencies trigger checks of all dependency files and
          // is what third party tools, such as melos, use to link up packages
          // for local development.
          'baz': {'path': '../local_baz'},
        },
      }),
      d.libDir('myapp'),
    ]).create();

    // Run pub.get to generate the dependency files.
    await pubGet();

    // Simulate a third party tool, modifying `package_config.json`.
    var thirdPartyToolFile = d.dir(appPath, [
      d.packageConfigFile([], generator: 'not-pub'),
    ]);
    await thirdPartyToolFile.create();
    await thirdPartyToolFile.validate();

    // Run the app with pub.run.
    final pub = await pubRun(args: ['lib/myapp.dart']);
    expect(
      pub.stdoutStream(),
      emits('Skipping dependency up-to-date checks: resolved by not-pub tool.'),
    );
    await pub.shouldExit(0);

    // Validate that the file was not overwritten.
    await thirdPartyToolFile.validate();
  });
}
