// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import 'package:pub/src/io.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('--dry-run shows report but does not apply changes', () async {
    await servePackages((builder) {
      builder.serve('foo', '1.0.0');
      builder.serve('foo', '2.0.0');
    });

    // Create the first lockfile.
    await d.appDir({'foo': '1.0.0'}).create();

    await pubGet();

    // Change the pubspec.
    await d.appDir({'foo': 'any'}).create();

    // Also delete the "packages" directory.
    deleteEntry(path.join(d.sandbox, appPath, 'packages'));

    // Do the dry run.
    await pubUpgrade(
        args: ['--dry-run'],
        output: allOf([
          contains('> foo 2.0.0 (was 1.0.0)'),
          contains('Would change 1 dependency.')
        ]));

    await d.dir(appPath, [
      // The lockfile should be unmodified.
      d.file('pubspec.lock', contains('1.0.0')),
      // The "packages" directory should not have been regenerated.
      d.nothing('packages')
    ]).validate();
  });
}
