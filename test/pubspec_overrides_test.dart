// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'descriptor.dart' as d;
import 'test_pub.dart';

void main() {
  forBothPubGetAndUpgrade((command) {
    test('supports dependency_overrides', () async {
      await servePackages()
        ..serve('lib', '1.0.0')
        ..serve('lib', '2.0.0');

      await d.dir(appPath, [
        d.appPubspec(dependencies: {'lib': '1.0.0'}),
        d.dir('lib'),
        d.pubspecOverrides({
          'dependency_overrides': {'lib': '2.0.0'}
        }),
      ]).create();

      final overridesPath = p.join('.', 'pubspec_overrides.yaml');
      await pubCommand(
        command,
        output: contains(
          '! lib 2.0.0 (overridden in $overridesPath)',
        ),
      );

      await d.dir(appPath, [
        d.packageConfigFile([
          d.packageConfigEntry(
            name: 'lib',
            version: '2.0.0',
            languageVersion: '3.0',
          ),
          d.packageConfigEntry(
            name: 'myapp',
            path: '.',
            languageVersion: '3.0',
          ),
        ])
      ]).validate();
    });
  });

  test('pubspec_overrides.yaml shadows overrides from pubspec.yaml', () async {
    await servePackages()
      ..serve('lib', '1.0.0')
      ..serve('lib', '2.0.0')
      ..serve('lib', '3.0.0')
      ..serve('foo', '1.0.0')
      ..serve('foo', '2.0.0');

    await d.dir(appPath, [
      d.appPubspec(
        dependencies: {'lib': '1.0.0', 'foo': '1.0.0'},
        extras: {
          'dependency_overrides': {'lib': '2.0.0', 'foo': '2.0.0'}
        },
      ),
      d.dir('lib'),
      // empty overrides file:
      d.pubspecOverrides({
        'dependency_overrides': {'lib': '3.0.0'}
      }),
    ]).create();

    final overridesPath = p.join('.', 'pubspec_overrides.yaml');
    await pubGet(
      output: allOf(
        contains('! lib 3.0.0 (overridden in $overridesPath)'),
        contains('+ foo 1.0.0 (2.0.0 available)'),
      ),
    );
  });
  test(
      "An empty pubspec_overrides.yaml doesn't shadow overrides from pubspec.yaml",
      () async {
    await servePackages()
      ..serve('lib', '1.0.0')
      ..serve('lib', '2.0.0');

    await d.dir(appPath, [
      d.appPubspec(
        dependencies: {
          'lib': '1.0.0',
        },
        extras: {
          'dependency_overrides': {'lib': '2.0.0'}
        },
      ),
      d.dir('lib'),
      // empty overrides file:
      d.pubspecOverrides({}),
    ]).create();

    await pubGet(
      output: contains('! lib 2.0.0 (overridden)'),
    );
  });
}
