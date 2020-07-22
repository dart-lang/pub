// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import 'package:pub/src/io.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('--breaking applies breaking changes and shows summary report',
      () async {
    await servePackages((builder) {
      builder.serve('foo', '1.0.0');
      builder.serve('foo', '2.0.0');
    });

    // Create the lockfile.
    await d.appDir({'foo': '1.0.0'}).create();

    await pubGet();

    // Recreating the appdir because the previous one only lasts for one
    // command.
    await d.appDir({'foo': '1.0.0'}).create();

    // Also delete the "packages" directory.
    deleteEntry(path.join(d.sandbox, appPath, 'packages'));

    // Do the dry run.
    await pubUpgrade(
        args: ['--breaking'],
        output: allOf([
          contains('1 breaking change(s) have been made:'),
          contains('foo: 1.0.0 -> ^2.0.0')
        ]));

    await d.dir(appPath, [
      // The pubspec file should be modified.
      d.pubspec({
        'name': 'myapp',
        'dependencies': {'foo': '^2.0.0'}
      }),
      // The lockfile should be modified.
      d.file('pubspec.lock', contains('2.0.0')),
      // The "packages" directory should not have been regenerated.
      d.nothing('packages')
    ]).validate();
  });
}
