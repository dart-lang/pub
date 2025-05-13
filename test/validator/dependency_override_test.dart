// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

void main() {
  test('should consider a package valid if it overrides dev dependency '
      'overrides', () async {
    final server = await servePackages();
    server.serve('foo', '3.0.0');
    await d.validPackage().create();

    await d.dir(appPath, [
      d.validPubspec(
        extras: {
          'dev_dependencies': {'foo': '^1.0.0'},
          'dependency_overrides': {'foo': '^3.0.0'},
        },
      ),
    ]).create();

    await expectValidation();
  });

  test('should consider a package valid '
      'if it has any dependency overrides on non-dependency', () async {
    final server = await servePackages();
    server.serve('foo', '3.0.0');
    server.serve('bar', '3.0.0');

    await d.validPackage().create();
    await d.dir(appPath, [
      d.validPubspec(
        extras: {
          'dev_dependencies': {'foo': '^1.0.0'},
          'dependency_overrides': {'foo': '^3.0.0', 'bar': '^3.0.0'},
        },
      ),
    ]).create();

    await expectValidation();
  });

  test(
    'should consider a package invalid if it has override of direct dependency',
    () async {
      final server = await servePackages();
      server.serve('foo', '3.0.0');
      await d.validPackage().create();

      await d.dir(appPath, [
        d.validPubspec(
          extras: {
            'dependencies': {'foo': '^1.0.0'},
            'dependency_overrides': {'foo': '^3.0.0'},
          },
        ),
      ]).create();

      await expectValidationHint(
        'Non-dev dependencies are overridden in pubspec.yaml.',
      );
    },
  );

  test('should consider a package invalid if it '
      'has override of transitive dependency', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0', deps: {'bar': '^3.0.0'});
    server.serve('bar', '3.0.0');

    await d.validPackage().create();

    await d.dir(appPath, [
      d.validPubspec(
        extras: {
          'dependencies': {'foo': '^1.0.0'},
          'dependency_overrides': {'bar': '^3.0.0'},
        },
      ),
    ]).create();

    await expectValidationHint(
      'Non-dev dependencies are overridden in pubspec.yaml.',
    );
  });

  test('reports correctly about a pubspec_overrides.yaml', () async {
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
        'dependency_overrides': {'foo': '3.0.0'},
      }),
    ]).create();

    await expectValidationHint(
      'Non-dev dependencies are overridden in pubspec_overrides.yaml.',
    );
  });

  test('Detects overrides from outside work-package', () async {
    final server = await servePackages();
    server.serve('foo', '3.0.0');
    await d.validPackage().create();

    await d.dir(appPath, [
      d.libPubspec(
        'workspace',
        '1.2.3',
        extras: {
          'workspace': ['a'],
          'dependency_overrides': {'foo': '^3.0.0'},
        },
        sdk: '^3.5.0',
      ),
      d.dir('a', [
        ...d.validPackage().contents,
        d.validPubspec(
          extras: {
            'environment': {'sdk': '^3.5.0'},
            'resolution': 'workspace',
            'dependencies': {'foo': '^1.0.0'},
          },
        ),
      ]),
    ]).create();

    final s = p.separator;
    await expectValidationHint(
      'Non-dev dependencies are overridden in ..${s}pubspec.yaml.',
      workingDirectory: p.join(d.sandbox, appPath, 'a'),
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
    );
  });
}
