// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

void main() {
  test(
      'should consider a package valid if it has dev dependency '
      'overrides', () async {
    final server = await servePackages();
    server.serve('foo', '3.0.0');
    await d.validPackage().create();

    await d.dir(appPath, [
      d.validPubspec(
        extras: {
          'dev_dependencies': {'foo': '^1.0.0'},
          'dependency_overrides': {'foo': '^3.0.0'}
        },
      )
    ]).create();

    await expectValidation();
  });

  group('should consider a package invalid if', () {
    test('it has only non-dev dependency overrides', () async {
      final server = await servePackages();
      server.serve('foo', '3.0.0');
      await d.validPackage().create();

      await d.dir(appPath, [
        d.validPubspec(
          extras: {
            'dependencies': {'foo': '^1.0.0'},
            'dependency_overrides': {'foo': '^3.0.0'}
          },
        )
      ]).create();

      await expectValidationHint(
        contains('Non-dev dependencies are overridden in pubspec.yaml.'),
      );
    });
    test('it has a pubspec_overrides.yaml', () async {
      final server = await servePackages();
      server.serve('foo', '3.0.0');
      await d.validPackage().create();

      await d.dir(appPath, [
        d.validPubspec(
          extras: {
            'dependencies': {'foo': '^1.0.0'},
          },
        ),
        d.pubspecOverrides({
          'dependency_overrides': {'foo': '3.0.0'}
        }),
      ]).create();

      await expectValidationHint(
        'Non-dev dependencies are overridden in pubspec_overrides.yaml.',
      );
    });

    test('it has any non-dev dependency overrides', () async {
      final server = await servePackages();
      server.serve('foo', '3.0.0');
      server.serve('bar', '3.0.0');

      await d.validPackage().create();
      await d.dir(appPath, [
        d.validPubspec(
          extras: {
            'dev_dependencies': {'foo': '^1.0.0'},
            'dependency_overrides': {
              'foo': '^3.0.0',
              'bar': '^3.0.0',
            }
          },
        )
      ]).create();

      await expectValidationHint(
        'Non-dev dependencies are overridden in pubspec.yaml.',
      );
    });
  });
}
