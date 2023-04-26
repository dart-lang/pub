// Copyright (c) 2021, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/validator.dart';
import 'package:pub/src/validator/leak_detection.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

Validator leakDetection() => LeakDetectionValidator();

void main() {
  group('should consider a package valid if it', () {
    setUp(d.validPackage().create);

    test('contains a source file without secrets', () async {
      await d.dir(appPath, [
        d.libPubspec('test_pkg', '1.0.0'),
        d.dir('lib', [
          d.file('test_pkg.dart', '''
            void main() => print('nothing secret here');
          '''),
        ])
      ]).create();
      await expectValidationDeprecated(leakDetection);
    });

    test('contains a source file listed in false_secrets', () async {
      await d.dir(appPath, [
        d.pubspec({
          'name': 'test_pkg',
          'version': '1.0.0',
          'false_secrets': [
            '/lib/test_pkg.dart',
          ],
        }),
        d.dir('lib', [
          d.file('test_pkg.dart', '''
            void main() => print('Revoked AWS key: AKIAVBOGPFGGW6HQOSMY');
          '''),
        ])
      ]).create();
      await expectValidationDeprecated(leakDetection, errors: isEmpty);
    });
  });

  group('should consider a package invalid if it', () {
    test('contains a source file with secrets', () async {
      await d.dir(appPath, [
        d.libPubspec('test_pkg', '1.0.0'),
        d.dir('lib', [
          d.file('test_pkg.dart', '''
            void main() => print('Revoked AWS key: AKIAVBOGPFGGW6HQOSMY');
          '''),
        ])
      ]).create();
      await expectValidationDeprecated(leakDetection, errors: isNotEmpty);
    });
  });

  group('should print', () {
    test('at-most 3 warnings', () async {
      await d.dir(appPath, [
        d.libPubspec('test_pkg', '1.0.0'),
        d.dir('lib', [
          d.file('test_pkg.dart', '''
            final apiKeys = [
              'AIzaSyDG0yD6347wy0i1U4ThqQoEZ0y37ZvFKPM',
              'AIzaSyCBSJpVO1A2yHOKP627dSmarIrdgvBygjw',
              'AIzaSyCB1pW0i5c5Wr42jykePxjrYOXwM4V4Kxk',
              'AIzaSyBg0xThpU0mAbbVgzm-BZ_4r3ByKwq8HQU',
              'AIzaSyDWpBgA7US5vfQnooBk1WsKa9U0ogKzuaI',
              'AIzaSyD95YyR7Xv1F7hdp503G6Tr2vi3CGDC27U',
              'AIzaSyCIKRF0KxSDxMkTAM7npQKQcASzRMItakw',
              'AIzaSyAH6KPIIZ5eXLrOX3l90su4YwYpaQ8X7cs',
              'AIzaSyCS78MPRLsd-Qkhc-t31OiaglmwstaU-nI',
              'AIzaSyAazCCPl4tWkSuDt9XBWRTpHxroViYhSxg',
            ];
          '''),
        ])
      ]).create();
      await expectValidationDeprecated(
        leakDetection,
        errors: allOf(
          hasLength(lessThanOrEqualTo(3)),
          contains(contains('10 potential leaks detected in 1 file:')),
        ),
      );
    });

    test('at-most 3 warnings when multiple files', () async {
      await d.dir(appPath, [
        d.libPubspec('test_pkg', '1.0.0'),
        d.dir('lib', [
          d.file('test_pkg.dart', '''
            final apiKeys = [
              'AIzaSyDG0yD6347wy0i1U4ThqQoEZ0y37ZvFKPM',
              'AIzaSyCBSJpVO1A2yHOKP627dSmarIrdgvBygjw',
              'AIzaSyCB1pW0i5c5Wr42jykePxjrYOXwM4V4Kxk',
              'AIzaSyBg0xThpU0mAbbVgzm-BZ_4r3ByKwq8HQU',
              'AIzaSyDWpBgA7US5vfQnooBk1WsKa9U0ogKzuaI',
              'AIzaSyD95YyR7Xv1F7hdp503G6Tr2vi3CGDC27U',
              'AIzaSyCIKRF0KxSDxMkTAM7npQKQcASzRMItakw',
            ];
          '''),
          d.file('helper.dart', '''
            final betterApiKeys = [
              'AIzaSyD95YyR7Xv1F7hdp503G6Tr2vi3CGDC27U',
              'AIzaSyCIKRF0KxSDxMkTAM7npQKQcASzRMItakw',
              'AIzaSyAH6KPIIZ5eXLrOX3l90su4YwYpaQ8X7cs',
              'AIzaSyCS78MPRLsd-Qkhc-t31OiaglmwstaU-nI',
              'AIzaSyAazCCPl4tWkSuDt9XBWRTpHxroViYhSxg',
            ];
          '''),
        ])
      ]).create();
      await expectValidationDeprecated(
        leakDetection,
        errors: allOf(
          hasLength(lessThanOrEqualTo(3)),
          contains(contains('12 potential leaks detected in 2 files:')),
        ),
      );
    });
  });

  group('LeakPattern', () {
    for (final pattern in leakPatterns) {
      group('for "${pattern.kind}"', () {
        for (var i = 0; i < pattern.testsWithLeaks.length; i++) {
          test('finds leak in testWithLeaks[$i]', () {
            final leaks = pattern
                .findPossibleLeaks('source.dart', pattern.testsWithLeaks[i])
                .toList(growable: false);
            expect(leaks, hasLength(equals(1)));
          });
        }

        for (var i = 0; i < pattern.testsWithNoLeaks.length; i++) {
          test('finds no leak in testsWithNoLeaks[$i]', () {
            final leaks = pattern
                .findPossibleLeaks('source.dart', pattern.testsWithNoLeaks[i])
                .toList(growable: false);
            expect(leaks, isEmpty);
          });
        }
      });
    }
  });
}
