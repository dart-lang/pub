// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:pub/src/io.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('--dry-run shows report but does not apply changes', () async {
    await servePackages()
      ..serve('foo', '1.0.0')
      ..serve('foo', '2.0.0');

    // Create the first lockfile.
    await d.appDir(dependencies: {'foo': '2.0.0'}).create();

    await pubGet();

    // Change the pubspec.
    await d.appDir(dependencies: {'foo': 'any'}).create();

    // Also delete the "packages" directory.
    deleteEntry(p.join(d.sandbox, appPath, 'packages'));

    // Do the dry run.
    await pubDowngrade(
      args: ['--dry-run'],
      output: allOf([
        contains('< foo 1.0.0'),
        contains('Would change 1 dependency.'),
      ]),
    );

    await d.dir(appPath, [
      // The lockfile should be unmodified.
      d.file('pubspec.lock', contains('2.0.0')),
      // The "packages" directory should not have been regenerated.
      d.nothing('packages'),
    ]).validate();
  });
}
