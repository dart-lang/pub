// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/validator.dart';
import 'package:pub/src/validator/relative_version_numbering.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

Validator validator() => RelativeVersionNumberingValidator();

Future<void> setup({required String sdkConstraint}) async {
  await d.validPackage().create();
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
  test('Hints about not publishing latest', () async {
    final server = await servePackages();
    server.serve(
      'test_pkg',
      '2.0.2',
    );
    await d.validPackage().create();

    await expectValidationHint('''
The latest published version is 2.0.2.
  Your version 1.0.0 is earlier than that.
''');
  });

  test('Hints incrementing more than needed', () async {
    final server = await servePackages();
    server.serve(
      'test_pkg',
      '1.0.2',
    );

    const notIncrementalHintText = '''
* The previous version is 1.0.2.
  
  It seems you are not publishing an incremental update.
  
  Consider one of:
  * 2.0.0 for a breaking release.
  * 1.1.0 for a minor release.
  * 1.0.3 for a patch release.
''';

    await d.validPackage(version: '1.0.4').create();
    await expectValidationHint(notIncrementalHintText);
    await d.validPackage(version: '1.3.0').create();
    await expectValidationHint(notIncrementalHintText);
    await d.validPackage(version: '1.1.1').create();
    await expectValidationHint(notIncrementalHintText);
  });

  test('Hints incrementing more than needed after a prerelease', () async {
    final server = await servePackages();
    server.serve(
      'test_pkg',
      '1.0.2-pre',
    );

    const notIncrementalHintText = '''
* The previous version is 1.0.2-pre.
  
  It seems you are not publishing an incremental update.
  
  Consider one of:
  * 2.0.0 for a breaking release.
  * 1.1.0 for a minor release.
  * 1.0.2 for a patch release.
''';

    await d.validPackage(version: '1.0.4').create();
    await expectValidationHint(notIncrementalHintText);
    await d.validPackage(version: '1.3.0').create();
    await expectValidationHint(notIncrementalHintText);
    await d.validPackage(version: '1.1.1').create();
    await expectValidationHint(notIncrementalHintText);
  });

  test('Hints incrementing more than after pre 1.0', () async {
    final server = await servePackages();
    server.serve(
      'test_pkg',
      '0.0.1',
    );

    const notIncrementalHintText = '''
* The previous version is 0.0.1.
  
  It seems you are not publishing an incremental update.
  
  Consider one of:
  * 1.0.0 for a first major release.
  * 0.1.0 for a breaking release.
  * 0.0.2 for a minor release.
''';

    await d.validPackage(version: '0.0.3').create();
    await expectValidationHint(notIncrementalHintText);
    await d.validPackage(version: '0.1.1').create();
    await expectValidationHint(notIncrementalHintText);
    await d.validPackage(version: '1.0.1').create();
    await expectValidationHint(notIncrementalHintText);
  });

  test('Releasing a prerelease of incremental version causes no hint',
      () async {
    final server = await servePackages();
    server.serve(
      'test_pkg',
      '1.0.0',
    );
    await d.validPackage(version: '1.0.1-dev').create();
    await expectValidation();
    await d.validPackage(version: '1.1.0-dev').create();
    await expectValidation();
    await d.validPackage(version: '2.0.0-dev').create();
    await expectValidation();
  });

  test('Releasing the prereleased version causes no hint', () async {
    final server = await servePackages();
    server.serve(
      'test_pkg',
      '1.0.0-dev',
    );
    await d.validPackage().create();
    await expectValidation();
  });

  group('should consider a package valid if it', () {
    test('is opting in to null-safety with previous null-safe version',
        () async {
      final server = await servePackages();
      server.serve(
        'test_pkg',
        '0.0.1',
        pubspec: {
          'environment': {'sdk': '>=2.12.0<3.0.0'}
        },
      );

      await setup(sdkConstraint: '>=2.12.0 <3.0.0');
      await expectValidationDeprecated(validator);
    });

    test(
        'is opting in to null-safety using a pre-release of 2.12.0 '
        'with previous null-safe version', () async {
      final server = await servePackages();
      server.serve(
        'test_pkg',
        '0.0.1',
        pubspec: {
          'environment': {'sdk': '>=2.12.0<3.0.0'}
        },
      );

      await setup(sdkConstraint: '>=2.12.0-dev <3.0.0');
      await expectValidationDeprecated(validator);
    });

    test(
        'is opting in to null-safety with previous null-safe version. '
        'Even with a later non-null-safe version', () async {
      await servePackages()
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
        );

      await setup(sdkConstraint: '>=2.12.0 <3.0.0');
      await expectValidationDeprecated(
        validator,
        hints: [
          // Nothing about null-safety
          '''
The latest published version is 2.0.1.
Your version 1.0.0 is earlier than that.'''
        ],
      );
    });

    test('is opting in to null-safety with no existing versions', () async {
      await setup(sdkConstraint: '>=2.12.0 <3.0.0');
      await servePackages();
      await expectValidationDeprecated(validator);
    });

    test(
        'opts in to null-safety, with previous stable version not-null-safe. '
        'With an in-between non-null-safe prerelease', () async {
      await servePackages()
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
        );

      await setup(sdkConstraint: '>=2.12.0 <3.0.0');
      await expectValidationDeprecated(validator);
    });
  });

  group('should warn if ', () {
    test('opts in to null-safety, with previous version not-null-safe',
        () async {
      final server = await servePackages();
      server.serve(
        'test_pkg',
        '0.0.1',
        pubspec: {
          'environment': {'sdk': '>=2.9.0<3.0.0'}
        },
      );

      await setup(sdkConstraint: '>=2.12.0 <3.0.0');
      await expectValidationDeprecated(
        validator,
        hints: [
          '''
You're about to publish a package that opts into null safety.
The previous version (0.0.1) isn't opted in.
See https://dart.dev/null-safety/migration-guide for best practices.'''
        ],
      );
    });

    test(
        'opts in to null-safety, with previous version not-null-safe. '
        'Even with a later null-safe version', () async {
      await servePackages()
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
        );

      await setup(sdkConstraint: '>=2.12.0 <3.0.0');
      await expectValidationDeprecated(
        validator,
        hints: [
          '''
The latest published version is 2.0.0.
Your version 1.0.0 is earlier than that.''',
          '''
You're about to publish a package that opts into null safety.
The previous version (0.0.1) isn't opted in.
See https://dart.dev/null-safety/migration-guide for best practices.'''
        ],
      );
    });

    test(
        'is opting in to null-safety with previous null-safe stable version. '
        'with an in-between non-null-safe prerelease', () async {
      await servePackages()
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
        );

      await setup(sdkConstraint: '>=2.12.0 <3.0.0');
      await expectValidationDeprecated(
        validator,
        hints: [
          '''
You're about to publish a package that opts into null safety.
The previous version (0.0.2-dev) isn't opted in.
See https://dart.dev/null-safety/migration-guide for best practices.'''
        ],
      );
    });

    test(
        'is opting in to null-safety with no existing stable versions. '
        'With a previous non-null-safe prerelease', () async {
      await setup(sdkConstraint: '>=2.12.0 <3.0.0');
      final server = await servePackages();
      server.serve(
        'test_pkg',
        '0.0.2-dev',
        pubspec: {
          'environment': {'sdk': '>=2.9.0<3.0.0'}
        },
      );
      await expectValidationDeprecated(
        validator,
        hints: [
          '''
You're about to publish a package that opts into null safety.
The previous version (0.0.2-dev) isn't opted in.
See https://dart.dev/null-safety/migration-guide for best practices.'''
        ],
      );
    });
  });
}
