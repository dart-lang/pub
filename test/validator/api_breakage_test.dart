// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'package:pub/src/validator/api_breakage.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

void main() {
  group('isBreakingVersionBump', () {
    test('1.0.0 to 1.0.1 is not breaking', () {
      expect(
        isBreakingVersionBump(Version.parse('1.0.0'), Version.parse('1.0.1')),
        isFalse,
      );
    });

    test('1.0.0 to 1.1.0 is not breaking', () {
      expect(
        isBreakingVersionBump(Version.parse('1.0.0'), Version.parse('1.1.0')),
        isFalse,
      );
    });

    test('1.0.0 to 2.0.0 is breaking', () {
      expect(
        isBreakingVersionBump(Version.parse('1.0.0'), Version.parse('2.0.0')),
        isTrue,
      );
    });

    test('1.0.0 to 2.0.0-dev is breaking', () {
      expect(
        isBreakingVersionBump(
          Version.parse('1.0.0'),
          Version.parse('2.0.0-dev'),
        ),
        isTrue,
      );
    });

    test('0.1.0 to 0.1.1 is not breaking', () {
      expect(
        isBreakingVersionBump(Version.parse('0.1.0'), Version.parse('0.1.1')),
        isFalse,
      );
    });

    test('0.1.0 to 0.2.0 is breaking', () {
      expect(
        isBreakingVersionBump(Version.parse('0.1.0'), Version.parse('0.2.0')),
        isTrue,
      );
    });

    test('0.2.0 to 0.3.0-wip is breaking', () {
      expect(
        isBreakingVersionBump(
          Version.parse('0.2.0'),
          Version.parse('0.3.0-wip'),
        ),
        isTrue,
      );
    });

    test('0.2.0 to 0.2.1-wip is not breaking', () {
      expect(
        isBreakingVersionBump(
          Version.parse('0.2.0'),
          Version.parse('0.2.1-wip'),
        ),
        isFalse,
      );
    });
  });

  group('ApiBreakageValidator', () {
    test('no warnings if package has never been published', () async {
      await servePackages();
      await d.validPackage().create();
      await expectValidation();
    });

    test('no warnings if no breaking changes are made', () async {
      final server = await servePackages();
      server.serve(
        'test_pkg',
        '1.0.0',
        pubspec: {
          'environment': {'sdk': '>=3.1.2 <=3.2.0'},
        },
        contents: [
          d.dir('lib', [
            d.file('test_pkg.dart', 'void foo() {}'),
          ]),
        ],
      );

      await d.dir(appPath, [
        d.validPubspec(extras: {'version': '1.1.0'}),
        d.file('LICENSE', 'Eh, do what you want.'),
        d.file('README.md', "This package isn't real."),
        d.file('CHANGELOG.md', '# 1.1.0\nFirst version\n'),
        d.dir('lib', [
          d.file('test_pkg.dart', 'void foo() {}\nvoid bar() {}'),
        ]),
      ]).create();

      await expectValidation();
    });

    test(
      'no warnings if breaking changes are accompanied by breaking bump',
      () async {
        final server = await servePackages();
        server.serve(
          'test_pkg',
          '1.0.0',
          pubspec: {
            'environment': {'sdk': '>=3.1.2 <=3.2.0'},
          },
          contents: [
            d.dir('lib', [
              d.file('test_pkg.dart', 'void foo() {}'),
            ]),
          ],
        );

        await d.dir(appPath, [
          d.validPubspec(extras: {'version': '2.0.0'}),
          d.file('LICENSE', 'Eh, do what you want.'),
          d.file('README.md', "This package isn't real."),
          d.file('CHANGELOG.md', '# 2.0.0\nFirst version\n'),
          d.dir('lib', [
            d.file('test_pkg.dart', 'void bar() {}'),
          ]),
        ]).create();

        await expectValidation();
      },
    );

    test(
      'no warnings if breaking changes are in a breaking prerelease bump',
      () async {
        final server = await servePackages();
        server.serve(
          'test_pkg',
          '0.2.0',
          pubspec: {
            'environment': {'sdk': '>=3.1.2 <=3.2.0'},
          },
          contents: [
            d.dir('lib', [
              d.file('test_pkg.dart', 'void foo() {}'),
            ]),
          ],
        );

        await d.dir(appPath, [
          d.validPubspec(extras: {'version': '0.3.0-wip'}),
          d.file('LICENSE', 'Eh, do what you want.'),
          d.file('README.md', "This package isn't real."),
          d.file('CHANGELOG.md', '# 0.3.0-wip\nFirst version\n'),
          d.dir('lib', [
            d.file('test_pkg.dart', 'void bar() {}'),
          ]),
        ]).create();

        await expectValidation();
      },
    );

    test(
      'warns if breaking changes are published with a minor version bump',
      () async {
        final server = await servePackages();
        server.serve(
          'test_pkg',
          '1.0.0',
          pubspec: {
            'environment': {'sdk': '>=3.1.2 <=3.2.0'},
          },
          contents: [
            d.dir('lib', [
              d.file('test_pkg.dart', 'void foo() {}'),
            ]),
          ],
        );

        await d.dir(appPath, [
          d.validPubspec(extras: {'version': '1.1.0'}),
          d.file('LICENSE', 'Eh, do what you want.'),
          d.file('README.md', "This package isn't real."),
          d.file('CHANGELOG.md', '# 1.1.0\nFirst version\n'),
          d.dir('lib', [
            d.file('test_pkg.dart', 'void bar() {}'),
          ]),
        ]).create();

        await expectValidationWarning(
          'Breaking API change(s) detected compared to published version '
          '1.0.0.',
        );
      },
    );
  });
}
