// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

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
    await _setupSdks();

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
Experiments enabled:
* `abc` for foo, myapp - New alphabetical feature
See https://dart.dev/go/experiments for more information.'''),
      environment: _environment,
    );

    final packageConfig = _readPackageConfig();
    expect(packageConfig.containsKey('experiments'), isFalse);
    expect(_experimentsByPackage(packageConfig), {
      'foo': ['abc'],
      'myapp': ['abc'],
    });
  });

  test('writes the experiments of each workspace package to its own '
      'package_config entry', () async {
    final server = await servePackages();
    await _setupSdks();
    server.serve(
      'foo',
      '1.0.0',
      pubspec: {
        'experiments': ['abc'],
      },
    );
    await d.dir(appPath, [
      d.libPubspec(
        'myapp',
        '1.0.0',
        sdk: '^3.5.0',
        extras: {
          'workspace': ['pkgs/a', 'pkgs/b'],
        },
      ),
      d.dir('pkgs', [
        d.dir('a', [
          d.libPubspec(
            'a',
            '1.0.0',
            deps: {'foo': '^1.0.0'},
            resolutionWorkspace: true,
            extras: {
              'experiments': ['abc'],
            },
          ),
        ]),
        d.dir('b', [d.libPubspec('b', '1.0.0', resolutionWorkspace: true)]),
      ]),
    ]).create();

    await pubGet(
      output: contains('* `abc` for a, foo - New alphabetical feature'),
      environment: {..._environment, '_PUB_TEST_SDK_VERSION': '3.5.0'},
    );

    // `b` and `myapp` don't opt in, so tools must not enable `abc` for them.
    expect(_experimentsByPackage(_readPackageConfig()), {
      'a': ['abc'],
      'foo': ['abc'],
    });
  });

  test('Finds the version with the right experiments enabled', () async {
    final server = await servePackages();
    await _setupSdks();
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
      environment: _environment,
    );
  });

  test('disallows experiments that are not enabled in the root', () async {
    final server = await servePackages();
    await _setupSdks();
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
      environment: _environment,
    );
  });

  test('disallows path dependencies using experiments that are not enabled '
      'in the root', () async {
    await servePackages();
    await _setupSdks();
    await d.dir('foo', [
      d.libPubspec(
        'foo',
        '1.0.0',
        extras: {
          'experiments': ['abc'],
        },
      ),
    ]).create();
    await d
        .appDir(
          dependencies: {
            'foo': {'path': '../foo'},
          },
        )
        .create();

    await pubGet(
      error: contains('The experiment `abc` has not been enabled.'),
      environment: _environment,
    );
  });

  test('allows dependencies to use experiments that are enabled by '
      'default', () async {
    final server = await servePackages();
    await _setupSdks();
    server.serve(
      'foo',
      '1.0.0',
      pubspec: {
        'experiments': ['shipped'],
      },
    );
    await d.appDir(dependencies: {'foo': '^1.0.0'}).create();

    await pubGet(
      output: allOf(
        contains('+ foo 1.0.0'),
        isNot(contains('Experiments enabled')),
      ),
      environment: _environment,
    );
    expect(_experimentsByPackage(_readPackageConfig()), isEmpty);
  });

  test('disallows experiments that are not enabled in the sdk', () async {
    await servePackages();
    await _setupSdks();
    await d
        .appDir(
          pubspec: {
            'experiments': <String>['abcd'],
          },
        )
        .create();

    await pubGet(
      error: contains('''
`abcd` is not a known experiment.

Available experiments are:
* `abc`: New alphabetical feature (https://dart.dev/experiments/abc)
* `main-only`: Only on main
* `shipped`: Already shipped

Read more about experiments at https://dart.dev/go/experiments.'''),
      environment: _environment,
      exitCode: DATA,
    );
  });

  test('disallows experiments listed more than once', () async {
    await servePackages();
    await _setupSdks();
    await d
        .appDir(
          pubspec: {
            'experiments': ['abc', 'abc'],
          },
        )
        .create();

    await pubGet(
      error: contains('The experiment `abc` is listed more than once.'),
      environment: _environment,
      exitCode: DATA,
    );
  });

  test('disallows experiments that are not available on the channel of the '
      'sdk', () async {
    await servePackages();
    await _setupSdks();
    await d
        .appDir(
          pubspec: {
            'experiments': ['main-only'],
          },
        )
        .create();

    await pubGet(
      error: contains(
        'The experiment `main-only` is only available on the main channel(s). '
        'This SDK is on the stable channel.',
      ),
      environment: {..._environment, '_PUB_TEST_SDK_CHANNEL': 'stable'},
      exitCode: DATA,
    );

    await pubGet(
      environment: {..._environment, '_PUB_TEST_SDK_CHANNEL': 'main'},
    );
    expect(_experimentsByPackage(_readPackageConfig()), {
      'myapp': ['main-only'],
    });
  });

  test('reads the experiments known by the Dart SDK', () async {
    await servePackages();
    await _setupSdks(
      dartExperiments: [
        {'name': 'dart-feature', 'description': 'A Dart feature'},
      ],
    );
    await d
        .appDir(
          pubspec: {
            'experiments': ['dart-feature'],
          },
        )
        .create();

    await pubGet(
      output: contains('* `dart-feature` for myapp - A Dart feature'),
      environment: _environment,
    );
    expect(_experimentsByPackage(_readPackageConfig()), {
      'myapp': ['dart-feature'],
    });
  });

  test('reads the experiments file in the format generated by the Dart '
      'SDK', () async {
    await servePackages();
    // Entries copied from sdk/lib/_internal/sdk_experiments.json in the Dart
    // SDK, which is generated by
    // pkg/front_end/tool/generate_experimental_flags.dart.
    await _setupSdks(
      dartExperimentsFile: {
        '_comment':
            'Generated from tools/experimental_features.yaml by '
            "'dart pkg/front_end/tool/cfe.dart generate-experimental-flags'. "
            'Do not edit.',
        'version': 1,
        'experiments': [
          {
            'name': 'class-modifiers',
            'description': 'Class modifiers',
            'enabledIn': '3.0.0',
            'expired': true,
            'experimentalReleaseVersion': '3.0.0',
          },
          {
            'name': 'data-assets',
            'description': 'Enable data assets in hooks.',
            'channels': ['main', 'dev'],
            'experimentalReleaseVersion': '3.14.0',
          },
          {
            'name': 'variance',
            'description': 'Sound variance',
            'experimentalReleaseVersion': '3.14.0',
          },
        ],
      },
    );
    await d
        .appDir(
          pubspec: {
            'experiments': ['data-assets', 'variance'],
          },
        )
        .create();

    await pubGet(
      error: contains(
        'The experiment `data-assets` is only available on the main, dev '
        'channel(s). This SDK is on the stable channel.',
      ),
      environment: {..._environment, '_PUB_TEST_SDK_CHANNEL': 'stable'},
      exitCode: DATA,
    );

    await pubGet(
      output: allOf(
        contains('* `data-assets` for myapp - Enable data assets in hooks.'),
        contains('* `variance` for myapp - Sound variance'),
      ),
      environment: {..._environment, '_PUB_TEST_SDK_CHANNEL': 'dev'},
    );
    expect(_experimentsByPackage(_readPackageConfig()), {
      'myapp': ['data-assets', 'variance'],
    });
  });

  test('rejects an experiments file with an unknown version', () async {
    await servePackages();
    await _setupSdks(
      dartExperimentsFile: {
        'version': 2,
        'experiments': [
          {'name': 'dart-feature', 'description': 'A Dart feature'},
        ],
      },
    );
    await d
        .appDir(
          pubspec: {
            'experiments': ['dart-feature'],
          },
        )
        .create();

    await pubGet(
      error: allOf(
        contains('has version 2'),
        contains('This version of pub only understands version 1.'),
      ),
      environment: _environment,
      exitCode: 1,
    );
  });

  test('warns about expired experiments and does not pass them on', () async {
    final server = await servePackages();
    await _setupSdks(
      dartExperiments: [
        {
          'name': 'shipped-and-expired',
          'description': 'Shipped a while ago',
          'enabledIn': '3.0.0',
          'expired': true,
        },
        {'name': 'abandoned', 'description': 'Never shipped', 'expired': true},
      ],
    );
    // Dependencies may list expired experiments that the root doesn't, and
    // pub doesn't warn about them.
    server.serve(
      'foo',
      '1.0.0',
      pubspec: {
        'experiments': ['abandoned'],
      },
    );
    await d
        .appDir(
          dependencies: {'foo': '^1.0.0'},
          pubspec: {
            'experiments': ['shipped-and-expired'],
          },
        )
        .create();

    await pubGet(
      warning: allOf(
        contains(
          'The experiment `shipped-and-expired` has been enabled by default '
          'since Dart 3.0.0. Remove it from `experiments` in the pubspec.yaml '
          'of myapp.',
        ),
        isNot(contains('`abandoned`')),
      ),
      environment: _environment,
    );
    expect(_experimentsByPackage(_readPackageConfig()), isEmpty);

    await d
        .appDir(
          dependencies: {'foo': '^1.0.0'},
          pubspec: {
            'experiments': ['abandoned'],
          },
        )
        .create();
    await pubGet(
      warning: contains(
        'The experiment `abandoned` has been retired and no longer has any '
        'effect. Remove it from `experiments` in the pubspec.yaml of myapp.',
      ),
      environment: _environment,
    );
    expect(_experimentsByPackage(_readPackageConfig()), isEmpty);
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
    await _setupSdks();

    await runPub(
      args: ['global', 'activate', 'foo', '--experiments', 'abc'],
      output: contains('* `abc` for foo - New alphabetical feature'),
      environment: _environment,
    );
  });
}

/// The environment making pub use the SDKs created by [_setupSdks].
Map<String, String> get _environment => {
  'FLUTTER_ROOT': p.join(sandbox, 'flutter'),
  'DART_ROOT': p.join(sandbox, 'dart-sdk'),
};

/// Creates a fake Flutter SDK and a fake Dart SDK, each with an experiments
/// file.
///
/// The Flutter SDK knows the experiments `abc`, `main-only` (only on the main
/// channel) and `shipped` (enabled by default). The Dart SDK knows
/// [dartExperiments], unless [dartExperimentsFile] gives the full contents of
/// its experiments file.
Future<void> _setupSdks({
  List<Map<String, Object?>> dartExperiments = const [],
  Map<String, Object?>? dartExperimentsFile,
}) async {
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
          {
            'name': 'main-only',
            'description': 'Only on main',
            'channels': ['main'],
          },
          {
            'name': 'shipped',
            'description': 'Already shipped',
            'enabledIn': '3.0.0',
          },
        ],
      }),
    ),
  ]).create();
  await d.dir('dart-sdk', [
    d.dir('lib', [
      d.dir('_internal', [
        d.file(
          'sdk_experiments.json',
          jsonEncode(dartExperimentsFile ?? {'experiments': dartExperiments}),
        ),
      ]),
    ]),
  ]).create();
}

Map<String, Object?> _readPackageConfig() =>
    json.decode(
          File(
            p.join(sandbox, appPath, '.dart_tool', 'package_config.json'),
          ).readAsStringSync(),
        )
        as Map<String, Object?>;

/// The `experiments` of the entries in [packageConfig] that have any, keyed by
/// package name.
Map<String, Object?> _experimentsByPackage(
  Map<String, Object?> packageConfig,
) => {
  for (final entry in (packageConfig['packages']! as List).cast<Map>())
    if (entry['experiments'] case final Object experiments)
      entry['name'] as String: experiments,
};
