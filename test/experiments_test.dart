// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub/src/exit_codes.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart';

import 'descriptor.dart' as d;
import 'test_pub.dart';

Future<void> main() async {
  test('allows experiments that are enabled in the root', () async {
    final server = await servePackages();
    await _setupFlutterRootWithExperiment();

    server.serve(
      'foo',
      '1.0.0',
      pubspec: {
        'experiments': ['abc'],
      },
    );
    await d
        .appDir(
          dependencies: {'foo': '^1.0.0'},
          pubspec: {
            'experiments': ['abc'],
          },
        )
        .create();

    await pubGet(
      output: contains('''
The following experiments have been enabled:
* abc (see https://dart.dev/experiments/abc)
'''),
      environment: {'FLUTTER_ROOT': p.join(sandbox, 'flutter')},
    );

    final packageConfig =
        json.decode(
              File(
                p.join(sandbox, appPath, '.dart_tool', 'package_config.json'),
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    expect(packageConfig['experiments'], ['abc']);
  });

  test('Finds the version with the right experiments enabled', () async {
    final server = await servePackages();
    await _setupFlutterRootWithExperiment();
    server.serve(
      'foo',
      '1.0.0-dev',
      pubspec: {
        'experiments': ['abc'],
      },
    );
    server.serve(
      'foo',
      '1.0.1-dev', // This version is newer, but uses a disabled experiment.
      pubspec: {
        'experiments': ['abcd'],
      },
    );
    await d
        .appDir(
          dependencies: {'foo': '^1.0.0-dev'},
          pubspec: {
            'experiments': ['abc'],
          },
        )
        .create();

    await pubGet(
      output: contains('+ foo 1.0.0-dev'),
      environment: {'FLUTTER_ROOT': p.join(sandbox, 'flutter')},
    );
  });

  test('disallows experiments that are not enabled in the root', () async {
    final server = await servePackages();
    await _setupFlutterRootWithExperiment();
    server.serve(
      'foo',
      '1.1.0-dev',
      pubspec: {
        'experiments': ['abc'],
      },
    );
    await d.appDir(dependencies: {'foo': '^1.0.0-dev'}).create();

    await pubGet(
      error: '''
Because myapp depends on foo any which requires enabling the experiment `abc`, version solving failed.

The experiment `abc` has not been enabled.

Currently no experiments are enabled.

To enable it add to your pubspec.yaml:

```
experiments:
  - abc
```

Read more about experiments at https://dart.dev/go/experiments.''',
      environment: {'FLUTTER_ROOT': p.join(sandbox, 'flutter')},
    );
  });

  test('disallows experiments that are not enabled in the sdk', () async {
    await servePackages();
    await _setupFlutterRootWithExperiment();
    await d
        .appDir(
          pubspec: {
            'experiments': <String>['abcd'],
          },
        )
        .create();

    await pubGet(
      error: contains('''
abcd is not a known experiment.

Available experiments are:
* abc: New alphabetical feature, https://dart.dev/experiments/abc

Read more about experiments at https://dart.dev/go/experiments.'''),
      environment: {'FLUTTER_ROOT': p.join(sandbox, 'flutter')},
      exitCode: DATA,
    );
  });

  test('Can global activate a package using experiments', () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      pubspec: {
        'experiments': ['abc'],
      },
    );
    await _setupFlutterRootWithExperiment();
    await d
        .appDir(
          pubspec: {
            'experiments': <String>['abcd'],
          },
        )
        .create();

    await runPub(
      args: ['global', 'activate', 'foo', '--experiments', 'abc'],
      output: contains('''
The following experiments have been enabled:
* abc (see https://dart.dev/experiments/abc)
'''),
      environment: {'FLUTTER_ROOT': p.join(sandbox, 'flutter')},
    );
  });
}

Future<void> _setupFlutterRootWithExperiment() async {
  await d.dir('flutter', [
    d.flutterVersion('1.2.3'),
    d.file(
      '.sdk_experiments.json',
      jsonEncode({
        'experiments': [
          {
            'name': 'abc',
            'description': 'New alphabetical feature',
            'docUrl': 'https://dart.dev/experiments/abc',
          },
        ],
      }),
    ),
  ]).create();
}
