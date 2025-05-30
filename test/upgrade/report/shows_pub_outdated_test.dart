// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('shows pub outdated', () async {
    await servePackages()
      ..serve('multiple_newer', '1.0.0')
      ..serve('multiple_newer', '1.0.1-unstable.1')
      ..serve('multiple_newer', '1.0.1')
      ..serve('multiple_newer', '1.0.2-unstable.1')
      ..serve('multiple_newer', '1.0.2-unstable.2')
      ..serve('multiple_newer_stable', '1.0.0')
      ..serve('multiple_newer_stable', '1.0.1')
      ..serve('multiple_newer_stable', '1.0.2')
      ..serve('multiple_newer_unstable', '1.0.0')
      ..serve('multiple_newer_unstable', '1.0.1-unstable.1')
      ..serve('multiple_newer_unstable', '1.0.1-unstable.2')
      ..serve('no_newer', '1.0.0')
      ..serve('one_newer_unstable', '1.0.0')
      ..serve('one_newer_unstable', '1.0.1-unstable.1')
      ..serve('one_newer_stable', '1.0.0')
      ..serve('one_newer_stable', '1.0.1');

    // Constraint everything to the first version.
    await d
        .appDir(
          dependencies: {
            'multiple_newer': '1.0.0',
            'multiple_newer_stable': '1.0.0',
            'multiple_newer_unstable': '1.0.0',
            'no_newer': '1.0.0',
            'one_newer_unstable': '1.0.0',
            'one_newer_stable': '1.0.0',
          },
        )
        .create();

    // Upgrade everything.
    await pubUpgrade(
      output: RegExp(r'''
3 packages have newer versions incompatible with dependency constraints.
Try `dart pub outdated` for more information.$''', multiLine: true),
    );

    // Running inside Flutter this will recommend the Flutter variant.
    await pubUpgrade(
      environment: {'PUB_ENVIRONMENT': 'flutter_cli:get'},
      output: RegExp(r'''
3 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.$''', multiLine: true),
    );

    // Upgrade `multiple_newer` to `1.0.1`.
    await d
        .appDir(
          dependencies: {
            'multiple_newer': '1.0.1',
            'multiple_newer_stable': '1.0.0',
            'multiple_newer_unstable': '1.0.0',
            'no_newer': '1.0.0',
            'one_newer_unstable': '1.0.0',
            'one_newer_stable': '1.0.0',
          },
        )
        .create();

    // Upgrade everything.
    await pubUpgrade(
      output: RegExp(r'''
2 packages have newer versions incompatible with dependency constraints.
Try `dart pub outdated` for more information.$''', multiLine: true),
    );

    // Upgrade `multiple_newer` to `1.0.2-unstable.1`.
    await d
        .appDir(
          dependencies: {
            'multiple_newer': '1.0.2-unstable.1',
            'multiple_newer_stable': '1.0.0',
            'multiple_newer_unstable': '1.0.0',
            'no_newer': '1.0.0',
            'one_newer_unstable': '1.0.0',
            'one_newer_stable': '1.0.0',
          },
        )
        .create();

    // Upgrade everything.
    await pubUpgrade(
      output: RegExp(r'''
3 packages have newer versions incompatible with dependency constraints.
Try `dart pub outdated` for more information.$''', multiLine: true),
    );

    // Upgrade all except `one_newer_stable`.
    await d
        .appDir(
          dependencies: {
            'multiple_newer': '1.0.2-unstable.2',
            'multiple_newer_stable': '1.0.2',
            'multiple_newer_unstable': '1.0.1-unstable.2',
            'no_newer': '1.0.0',
            'one_newer_unstable': '1.0.1-unstable.1',
            'one_newer_stable': '1.0.0',
          },
        )
        .create();

    // Upgrade everything.
    await pubUpgrade(
      output: RegExp(r'''
1 package has newer versions incompatible with dependency constraints.
Try `dart pub outdated` for more information.$''', multiLine: true),
    );
  });
}
