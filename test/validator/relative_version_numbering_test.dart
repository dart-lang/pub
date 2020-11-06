// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/entrypoint.dart';
import 'package:pub/src/validator.dart';
import 'package:pub/src/validator/relative_version_numbering.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

Validator validator(Entrypoint entrypoint) =>
    RelativeVersionNumberingValidator(entrypoint, globalPackageServer.url);

Future<void> setup({String sdkConstraint}) async {
  await d.validPackage.create();
  await d.dir(appPath, [
    d.pubspec({
      'name': 'test_pkg',
      'version': '1.0.0',
      'environment': {'sdk': sdkConstraint},
    }),
  ]).create();

  await pubGet(environment: {'_PUB_TEST_SDK_VERSION': '2.12.0'});
}

void main() {
  group('should consider a package valid if it', () {
    test('is not opting in to null-safety with previous non-null-safe version',
        () async {
      await servePackages(
        (server) => server.serve(
          'test_pkg',
          '0.0.1',
          pubspec: {
            'environment': {'sdk': '>=2.9.0<3.0.0'}
          },
        ),
      );

      await setup(sdkConstraint: '>=2.9.0 <3.0.0');
      await expectValidation(validator);
    });

    test(
        'is not opting in to null-safety with previous non-null-safe version. '
        'Even with a later null-safe version', () async {
      await servePackages(
        (server) => server
          ..serve(
            'test_pkg',
            '0.0.1',
            pubspec: {
              'environment': {'sdk': '>=2.9.0<3.0.0'}
            },
          )
          ..serve(
            'test_pkg',
            '2.0.0',
            pubspec: {
              'environment': {'sdk': '>=2.12.0<3.0.0'}
            },
          ),
      );

      await setup(sdkConstraint: '>=2.9.0 <3.0.0');
      await expectValidation(validator);
    });

    test('is opting in to null-safety with previous null-safe version',
        () async {
      await servePackages(
        (server) => server.serve(
          'test_pkg',
          '0.0.1',
          pubspec: {
            'environment': {'sdk': '>=2.12.0<3.0.0'}
          },
        ),
      );

      await setup(sdkConstraint: '>=2.12.0 <3.0.0');
      await expectValidation(validator);
    });

    test(
        'is opting in to null-safety using a pre-release of 2.12.0 '
        'with previous null-safe version', () async {
      await servePackages(
        (server) => server.serve(
          'test_pkg',
          '0.0.1',
          pubspec: {
            'environment': {'sdk': '>=2.12.0<3.0.0'}
          },
        ),
      );

      await setup(sdkConstraint: '>=2.12.0-dev <3.0.0');
      await expectValidation(validator);
    });

    test(
        'is opting in to null-safety with previous null-safe version. '
        'Even with a later non-null-safe version', () async {
      await servePackages(
        (server) => server
          ..serve(
            'test_pkg',
            '0.0.1',
            pubspec: {
              'environment': {'sdk': '>=2.12.0<3.0.0'}
            },
          )
          ..serve(
            'test_pkg',
            '2.0.1',
            pubspec: {
              'environment': {'sdk': '>=2.9.0<3.0.0'}
            },
          ),
      );

      await setup(sdkConstraint: '>=2.12.0 <3.0.0');
      await expectValidation(validator);
    });

    test('is opting in to null-safety with no existing versions', () async {
      await setup(sdkConstraint: '>=2.12.0 <3.0.0');
      await servePackages((x) => x);
      await expectValidation(validator);
    });

    test('is not opting in to null-safety with no existing versions', () async {
      await setup(sdkConstraint: '>=2.9.0 <3.0.0');
      await servePackages((x) => x);

      await expectValidation(validator);
    });

    test(
        'is not opting in to null-safety with previous null-safe stable version. '
        'With an in-between not null-safe prerelease', () async {
      await servePackages(
        (server) => server
          ..serve(
            'test_pkg',
            '0.0.1',
            pubspec: {
              'environment': {'sdk': '>=2.12.0<3.0.0'}
            },
          )
          ..serve(
            'test_pkg',
            '0.0.2-dev',
            pubspec: {
              'environment': {'sdk': '>=2.9.0<3.0.0'}
            },
          ),
      );

      await setup(sdkConstraint: '>=2.9.0 <3.0.0');
      await expectValidation(validator);
    });

    test(
        'opts in to null-safety, with previous stable version not-null-safe. '
        'With an in-between non-null-safe prerelease', () async {
      await servePackages(
        (server) => server
          ..serve(
            'test_pkg',
            '0.0.1',
            pubspec: {
              'environment': {'sdk': '>=2.9.0<3.0.0'}
            },
          )
          ..serve(
            'test_pkg',
            '0.0.2-dev',
            pubspec: {
              'environment': {'sdk': '>=2.12.0<3.0.0'}
            },
          ),
      );

      await setup(sdkConstraint: '>=2.12.0 <3.0.0');
      await expectValidation(validator);
    });
  });

  group('should warn if ', () {
    test('opts in to null-safety, with previous version not-null-safe',
        () async {
      await servePackages(
        (server) => server.serve(
          'test_pkg',
          '0.0.1',
          pubspec: {
            'environment': {'sdk': '>=2.9.0<3.0.0'}
          },
        ),
      );

      await setup(sdkConstraint: '>=2.12.0 <3.0.0');
      await expectValidation(validator, hints: isNotEmpty);
    });

    test(
        'is not opting in to null-safety with no existing stable versions. '
        'With a previous in-between null-safe prerelease', () async {
      await setup(sdkConstraint: '>=2.9.0 <3.0.0');
      await servePackages(
        (server) => server.serve(
          'test_pkg',
          '0.0.2-dev',
          pubspec: {
            'environment': {'sdk': '>=2.12.0<3.0.0'}
          },
        ),
      );

      await expectValidation(validator, hints: isNotEmpty);
    });
    test(
        'is not opting in to null-safety with previous non-null-safe stable version. '
        'With an in-between null-safe prerelease', () async {
      await servePackages(
        (server) => server
          ..serve(
            'test_pkg',
            '0.0.1',
            pubspec: {
              'environment': {'sdk': '>=2.9.0<3.0.0'}
            },
          )
          ..serve(
            'test_pkg',
            '0.0.2-dev',
            pubspec: {
              'environment': {'sdk': '>=2.12.0<3.0.0'}
            },
          ),
      );

      await setup(sdkConstraint: '>=2.9.0 <3.0.0');
      await expectValidation(validator, hints: isNotEmpty);
    });

    test(
        'opts in to null-safety, with previous version not-null-safe. '
        'Even with a later null-safe version', () async {
      await servePackages(
        (server) => server
          ..serve(
            'test_pkg',
            '0.0.1',
            pubspec: {
              'environment': {'sdk': '>=2.9.0<3.0.0'}
            },
          )
          ..serve(
            'test_pkg',
            '2.0.0',
            pubspec: {
              'environment': {'sdk': '>=2.12.0<3.0.0'}
            },
          ),
      );

      await setup(sdkConstraint: '>=2.12.0 <3.0.0');
      await expectValidation(validator, hints: isNotEmpty);
    });

    test('is not opting in to null-safety with previous null-safe version',
        () async {
      await servePackages(
        (server) => server.serve(
          'test_pkg',
          '0.0.1',
          pubspec: {
            'environment': {'sdk': '>=2.12.0<3.0.0'}
          },
        ),
      );

      await setup(sdkConstraint: '>=2.9.0 <3.0.0');
      await expectValidation(validator, hints: isNotEmpty);
    });

    test(
        'is not opting in to null-safety with previous null-safe version. '
        'Even with a later non-null-safe version', () async {
      await servePackages(
        (server) => server
          ..serve(
            'test_pkg',
            '0.0.1',
            pubspec: {
              'environment': {'sdk': '>=2.12.0<3.0.0'}
            },
          )
          ..serve(
            'test_pkg',
            '2.0.0',
            pubspec: {
              'environment': {'sdk': '>=2.9.0<3.0.0'}
            },
          ),
      );

      await setup(sdkConstraint: '>=2.9.0 <3.0.0');
      await expectValidation(validator, hints: isNotEmpty);
    });

    test(
        'is opting in to null-safety with previous null-safe stable version. '
        'with an in-between non-null-safe prerelease', () async {
      await servePackages(
        (server) => server
          ..serve(
            'test_pkg',
            '0.0.1',
            pubspec: {
              'environment': {'sdk': '>=2.12.0<3.0.0'}
            },
          )
          ..serve(
            'test_pkg',
            '0.0.2-dev',
            pubspec: {
              'environment': {'sdk': '>=2.9.0<3.0.0'}
            },
          ),
      );

      await setup(sdkConstraint: '>=2.12.0 <3.0.0');
      await expectValidation(validator, hints: isNotEmpty);
    });

    test(
        'is opting in to null-safety with no existing stable versions. '
        'With a previous non-null-safe prerelease', () async {
      await setup(sdkConstraint: '>=2.12.0 <3.0.0');
      await servePackages(
        (server) => server.serve(
          'test_pkg',
          '0.0.2-dev',
          pubspec: {
            'environment': {'sdk': '>=2.9.0<3.0.0'}
          },
        ),
      );
      await expectValidation(validator, hints: isNotEmpty);
    });
  });
}
