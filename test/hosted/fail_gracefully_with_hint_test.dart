// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../golden_file.dart';
import '../test_pub.dart';

void main() {
  testWithGolden('hint: try without --offline', (ctx) async {
    // Run the server so that we know what URL to use in the system cache.
    (await servePackages()).serveErrors();

    await d.appDir(dependencies: {'foo': 'any'}).create();

    await pubGet(
      args: ['--offline'],
      exitCode: exit_codes.UNAVAILABLE,
      error: contains('Try again without --offline!'),
    );
  });

  testWithGolden('supports two hints', (ctx) async {
    // Run the server so that we know what URL to use in the system cache.
    (await servePackages()).serveErrors();

    await d.hostedCache([
      d.dir('foo-1.2.3', [
        d.pubspec({
          'name': 'foo',
          'version': '1.2.3',
          'environment': {
            'flutter': 'any', // generates hint -> flutter pub get
          },
        }),
      ]),
      d.dir('foo-1.2.4', [
        d.pubspec({
          'name': 'foo',
          'version': '1.2.4',
          'dependencies': {
            'bar': 'any', // generates hint -> try without --offline
          },
        }),
      ]),
    ]).create();

    await d.appDir(dependencies: {'foo': 'any'}).create();

    await pubGet(
      args: ['--offline'],
      exitCode: exit_codes.UNAVAILABLE,
      error: allOf(
        contains('Try again without --offline!'),
        contains('flutter pub get'), // hint that
      ),
    );

    await ctx.run(['get', '--offline']);
  });
}
