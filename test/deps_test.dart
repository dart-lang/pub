// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'descriptor.dart' as d;
import 'test_pub.dart';

void main() {
  setUp(() async {
    await servePackages((builder) {
      builder.serve('normal', '1.2.3',
          deps: {'transitive': 'any', 'circular_a': 'any'});
      builder.serve('transitive', '1.2.3', deps: {'shared': 'any'});
      builder.serve('shared', '1.2.3', deps: {'other': 'any'});
      builder.serve('dev_only', '1.2.3');
      builder.serve('unittest', '1.2.3',
          deps: {'shared': 'any', 'dev_only': 'any'});
      builder.serve('other', '1.0.0', deps: {'myapp': 'any'});
      builder.serve('overridden', '1.0.0');
      builder.serve('overridden', '2.0.0');
      builder.serve('override_only', '1.2.3');
      builder.serve('circular_a', '1.2.3', deps: {'circular_b': 'any'});
      builder.serve('circular_b', '1.2.3', deps: {'circular_a': 'any'});
    });

    await d.dir('from_path',
        [d.libDir('from_path'), d.libPubspec('from_path', '1.2.3')]).create();

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependencies': {
          'normal': 'any',
          'overridden': '1.0.0',
          'from_path': {'path': '../from_path'}
        },
        'dev_dependencies': {'unittest': 'any'},
        'dependency_overrides': {'overridden': '2.0.0', 'override_only': 'any'}
      })
    ]).create();
  });

  group('lists all dependencies', () {
    test('in compact form', () async {
      await pubGet();
      await runPub(args: ['deps', '-s', 'compact'], output: '''
          Dart SDK 0.1.2+3
          myapp 0.0.0

          dependencies:
          - from_path 1.2.3
          - normal 1.2.3 [transitive circular_a]
          - overridden 2.0.0

          dev dependencies:
          - unittest 1.2.3 [shared dev_only]

          dependency overrides:
          - overridden 2.0.0
          - override_only 1.2.3

          transitive dependencies:
          - circular_a 1.2.3 [circular_b]
          - circular_b 1.2.3 [circular_a]
          - dev_only 1.2.3
          - other 1.0.0 [myapp]
          - shared 1.2.3 [other]
          - transitive 1.2.3 [shared]
          ''');
    });

    test('in list form', () async {
      await pubGet();
      await runPub(args: ['deps', '--style', 'list'], output: '''
          Dart SDK 0.1.2+3
          myapp 0.0.0

          dependencies:
          - normal 1.2.3
            - transitive any
            - circular_a any
          - overridden 2.0.0
          - from_path 1.2.3

          dev dependencies:
          - unittest 1.2.3
            - shared any
            - dev_only any

          dependency overrides:
          - overridden 2.0.0
          - override_only 1.2.3

          transitive dependencies:
          - circular_a 1.2.3
            - circular_b any
          - circular_b 1.2.3
            - circular_a any
          - dev_only 1.2.3
          - other 1.0.0
            - myapp any
          - shared 1.2.3
            - other any
          - transitive 1.2.3
            - shared any
          ''');
    });

    test('in tree form', () async {
      await pubGet();
      await runPub(args: ['deps'], output: '''
          Dart SDK 0.1.2+3
          myapp 0.0.0
          |-- from_path 1.2.3
          |-- normal 1.2.3
          |   |-- circular_a 1.2.3
          |   |   '-- circular_b 1.2.3
          |   |       '-- circular_a...
          |   '-- transitive 1.2.3
          |       '-- shared...
          |-- overridden 2.0.0
          |-- override_only 1.2.3
          '-- unittest 1.2.3
              |-- dev_only 1.2.3
              '-- shared 1.2.3
                  '-- other 1.0.0
                      '-- myapp...
          ''');
    });

    test('with the Flutter SDK, if applicable', () async {
      await pubGet();

      await d.dir('flutter', [d.file('version', '4.3.2+1')]).create();
      await runPub(
          args: ['deps'],
          output: contains('Flutter SDK 4.3.2+1'),
          environment: {'FLUTTER_ROOT': p.join(d.sandbox, 'flutter')});
    });

    test('with the Fuchsia SDK, if applicable', () async {
      await pubGet();

      await d.dir('fuchsia', [d.file('version', '4.3.2+1')]).create();
      await runPub(
          args: ['deps'],
          output: contains('Fuchsia SDK 4.3.2+1'),
          environment: {'FUCHSIA_DART_SDK_ROOT': p.join(d.sandbox, 'fuchsia')});
    });
  });

  group('lists non-dev dependencies', () {
    test('in compact form', () async {
      await pubGet();
      await runPub(args: ['deps', '-s', 'compact', '--no-dev'], output: '''
          Dart SDK 0.1.2+3
          myapp 0.0.0

          dependencies:
          - from_path 1.2.3
          - normal 1.2.3 [transitive circular_a]
          - overridden 2.0.0

          dependency overrides:
          - overridden 2.0.0
          - override_only 1.2.3

          transitive dependencies:
          - circular_a 1.2.3 [circular_b]
          - circular_b 1.2.3 [circular_a]
          - other 1.0.0 [myapp]
          - shared 1.2.3 [other]
          - transitive 1.2.3 [shared]
          ''');
    });

    test('in list form', () async {
      await pubGet();
      await runPub(args: ['deps', '--style', 'list', '--no-dev'], output: '''
          Dart SDK 0.1.2+3
          myapp 0.0.0

          dependencies:
          - normal 1.2.3
            - transitive any
            - circular_a any
          - overridden 2.0.0
          - from_path 1.2.3

          dependency overrides:
          - overridden 2.0.0
          - override_only 1.2.3

          transitive dependencies:
          - circular_a 1.2.3
            - circular_b any
          - circular_b 1.2.3
            - circular_a any
          - other 1.0.0
            - myapp any
          - shared 1.2.3
            - other any
          - transitive 1.2.3
            - shared any
          ''');
    });

    test('in tree form', () async {
      await pubGet();
      await runPub(args: ['deps', '--no-dev'], output: '''
          Dart SDK 0.1.2+3
          myapp 0.0.0
          |-- from_path 1.2.3
          |-- normal 1.2.3
          |   |-- circular_a 1.2.3
          |   |   '-- circular_b 1.2.3
          |   |       '-- circular_a...
          |   '-- transitive 1.2.3
          |       '-- shared 1.2.3
          |           '-- other 1.0.0
          |               '-- myapp...
          |-- overridden 2.0.0
          '-- override_only 1.2.3
          ''');
    });
  });
}
