// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

Future<void> expectValidation(error, int exitCode) async {
  await runPub(
    error: error,
    args: ['publish', '--dry-run'],
    environment: {'_PUB_TEST_SDK_VERSION': '2.12.0'},
    workingDirectory: d.path(appPath),
    exitCode: exitCode,
  );
}

Future<void> setup({
  String sdkConstraint,
  Map dependencies = const {},
  Map devDependencies = const {},
  List<d.Descriptor> extraFiles = const [],
}) async {
  await d.validPackage.create();
  await d.dir(appPath, [
    d.pubspec({
      'name': 'test_pkg',
      'description':
          'A just long enough decription to fit the requirement of 60 characters',
      'homepage': 'https://example.com/',
      'version': '1.0.0',
      'environment': {'sdk': sdkConstraint},
      'dependencies': dependencies,
      'dev_dependencies': devDependencies,
    }),
    ...extraFiles,
  ]).create();

  await pubGet(environment: {'_PUB_TEST_SDK_VERSION': '2.12.0'});
}

void main() {
  group('should consider a package valid if it', () {
    test('is not opting in to null-safety, but depends on package that is',
        () async {
      await servePackages(
        (server) => server.serve(
          'foo',
          '0.0.1',
          pubspec: {
            'environment': {'sdk': '>=2.12.0<3.0.0'}
          },
        ),
      );

      await setup(
          sdkConstraint: '>=2.9.0 <3.0.0', dependencies: {'foo': '^0.0.1'});
      await expectValidation(contains('Package has 0 warnings.'), 0);
    });
    test('is opting in to null-safety and depends on package that is',
        () async {
      await servePackages(
        (server) => server.serve(
          'foo',
          '0.0.1',
          pubspec: {
            'environment': {'sdk': '>=2.12.0<3.0.0'}
          },
        ),
      );

      await setup(
          sdkConstraint: '>=2.12.0 <3.0.0', dependencies: {'foo': '^0.0.1'});
      await expectValidation(contains('Package has 0 warnings.'), 0);
    });

    test('is opting in to null-safety has dev_dependency that is not',
        () async {
      await servePackages(
        (server) => server.serve(
          'foo',
          '0.0.1',
          pubspec: {
            'environment': {'sdk': '>=2.9.0<3.0.0'}
          },
        ),
      );

      await setup(sdkConstraint: '>=2.12.0 <3.0.0', devDependencies: {
        'foo': '^0.0.1',
      });
      await expectValidation(contains('Package has 0 warnings.'), 0);
    });
  });

  group('should consider a package invalid if it', () {
    test('is opting in to null-safety, but depends on package that is not',
        () async {
      await servePackages(
        (server) => server.serve(
          'foo',
          '0.0.1',
          pubspec: {
            'environment': {'sdk': '>=2.9.0<3.0.0'}
          },
        ),
      );

      await setup(
          sdkConstraint: '>=2.12.0 <3.0.0', dependencies: {'foo': '^0.0.1'});
      await expectValidation(
          allOf(
            contains(
                'package:foo is not opted into null safety in its pubspec.yaml:'),
            contains('Package has 1 warning.'),
          ),
          65);
    });

    test('is opting in to null-safety, but has file opting out', () async {
      await setup(sdkConstraint: '>=2.12.0 <3.0.0', extraFiles: [
        d.dir('lib', [d.file('a.dart', '// @dart = 2.9\n')])
      ]);
      await expectValidation(
          allOf(
            contains('package:test_pkg/a.dart is opting out of null safety:'),
            contains('Package has 1 warning.'),
          ),
          65);
    });

    test(
        'is opting in to null-safety, but depends on package has file opting out',
        () async {
      await servePackages(
        (server) => server.serve('foo', '0.0.1', pubspec: {
          'environment': {'sdk': '>=2.12.0<3.0.0'}
        }, contents: [
          d.dir('lib', [
            d.file('foo.dart', '''
// @dart = 2.9
          ''')
          ])
        ]),
      );

      await setup(
          sdkConstraint: '>=2.12.0 <3.0.0', dependencies: {'foo': '^0.0.1'});
      await expectValidation(
          allOf(
            contains('package:foo/foo.dart is opting out of null safety:'),
            contains('Package has 1 warning.'),
          ),
          65);
    });
  });
}
