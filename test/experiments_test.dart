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
        'experiments': {
          'enable': ['abc'],
        },
      },
    );
    await d
        .appDir(
          dependencies: {'foo': '^1.0.0'},
          pubspec: {
            'experiments': {
              'enable': ['abc'],
            },
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
        'experiments': {
          'enable': ['abc'],
        },
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
              'experiments': {
                'enable': ['abc'],
              },
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
        'experiments': {
          'enable': ['abc'],
        },
      },
    );
    server.serve(
      'foo',
      '1.0.1-dev', // This version is newer, but uses a disabled experiment.
      pubspec: {
        'experiments': {
          'enable': ['abcd'],
        },
      },
    );
    await d
        .appDir(
          dependencies: {'foo': '^1.0.0-dev'},
          pubspec: {
            'experiments': {
              'enable': ['abc'],
            },
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
        'experiments': {
          'enable': ['abc'],
        },
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
  enable:
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
          'experiments': {
            'enable': ['abc'],
          },
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
        'experiments': {
          'enable': ['shipped'],
        },
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
            'experiments': {
              'enable': <String>['abcd'],
            },
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
            'experiments': {
              'enable': ['abc', 'abc'],
            },
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
            'experiments': {
              'enable': ['main-only'],
            },
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
            'experiments': {
              'enable': ['dart-feature'],
            },
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
            'experiments': {
              'enable': ['data-assets', 'variance'],
            },
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
            'experiments': {
              'enable': ['dart-feature'],
            },
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
        'experiments': {
          'enable': ['abandoned'],
        },
      },
    );
    await d
        .appDir(
          dependencies: {'foo': '^1.0.0'},
          pubspec: {
            'experiments': {
              'enable': ['shipped-and-expired'],
            },
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
            'experiments': {
              'enable': ['abandoned'],
            },
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
    await d
        .appDir(
          dependencies: {'foo': '^1.0.0'},
          pubspec: {
            'experiments': {
              'enable': ['no-shipped-and-expired'],
            },
          },
        )
        .create();
    await pubGet(
      warning: contains(
        'The experiment `shipped-and-expired` has been enabled by default '
        'since Dart 3.0.0 and can no longer be disabled. Remove '
        '`no-shipped-and-expired` from `experiments` in the pubspec.yaml of '
        'myapp.',
      ),
      environment: _environment,
    );
    expect(_experimentsByPackage(_readPackageConfig()), isEmpty);
  });

  test('can opt out of an experiment enabled by default', () async {
    final server = await servePackages();
    await _setupSdks();
    // A dependency can opt out of a default-enabled experiment without the
    // root package having to list it.
    server.serve(
      'foo',
      '1.0.0',
      pubspec: {
        'experiments': {
          'enable': ['no-shipped'],
        },
      },
    );
    await d
        .appDir(
          dependencies: {'foo': '^1.0.0'},
          pubspec: {
            'experiments': {
              'enable': ['no-shipped', 'no-abc'],
            },
          },
        )
        .create();

    await pubGet(
      output: allOf(
        contains('* `no-shipped` for foo, myapp - Already shipped'),
        isNot(contains('no-abc')),
      ),
      environment: _environment,
    );
    expect(_experimentsByPackage(_readPackageConfig()), {
      'foo': ['no-shipped'],
      'myapp': ['no-shipped'],
    });
  });

  test('rejects enabling and disabling the same experiment', () async {
    await _setupSdks();
    await d
        .appDir(
          pubspec: {
            'experiments': {
              'enable': ['shipped', 'no-shipped'],
            },
          },
        )
        .create();

    await pubGet(
      error: contains(
        'The experiment `shipped` cannot be both enabled and disabled.',
      ),
      environment: _environment,
      exitCode: DATA,
    );
  });

  test('Can global activate a package using experiments', () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      pubspec: {
        'experiments': {
          'enable': ['abc'],
        },
      },
    );
    await _setupSdks();

    await runPub(
      args: ['global', 'activate', 'foo', '--experiments', 'abc'],
      output: contains('* `abc` for foo - New alphabetical feature'),
      environment: _environment,
    );
  });

  test(
    'supports package-scoped experiments (<package>.<experiment>)',
    () async {
      final server = await servePackages();
      await _setupSdks();
      server.serve(
        'foo',
        '1.0.0',
        pubspec: {
          'experiments': {
            'declare': {
              'new_api': {
                'description': 'New experimental API',
                'docUrl': 'https://example.com/new_api',
              },
              'graduated_api': {
                'description': 'Graduated API',
                'enabledIn': '0.9.0',
              },
              'retired_api': {'description': 'Retired API', 'expired': true},
            },
          },
        },
      );
      server.serve(
        'bar',
        '1.0.0-dev',
        deps: {'foo': '^1.0.0'},
        pubspec: {
          'experiments': {
            'enable': ['foo.new_api', 'foo.graduated_api'],
          },
        },
      );

      // Fails when `bar` requires `foo.new_api` and root does not opt in.
      await d.appDir(dependencies: {'bar': '^1.0.0-dev'}).create();
      await pubGet(
        error: contains('The experiment `foo.new_api` has not been enabled.'),
        environment: _environment,
      );

      // Succeeds when root opts into `foo.new_api` (using map syntax with
      // both `enable` and `declare`). Graduated and retired experiments emit
      // warnings and are omitted from package_config.json.
      await d
          .appDir(
            dependencies: {'bar': '^1.0.0-dev'},
            pubspec: {
              'experiments': {
                'enable': [
                  'foo.new_api',
                  'foo.graduated_api',
                  'foo.retired_api',
                ],
                'declare': {
                  'app_exp': {'description': 'App experiment'},
                },
              },
            },
          )
          .create();
      await pubGet(
        output: contains(
          '* `foo.new_api` for bar, myapp - New experimental API',
        ),
        warning: allOf(
          contains(
            'The experiment `foo.graduated_api` has been enabled by default '
            'since foo 0.9.0. Remove it from `experiments` in the pubspec.yaml '
            'of myapp.',
          ),
          contains(
            'The experiment `foo.retired_api` has been retired and no longer '
            'has any effect. Remove it from `experiments` in the pubspec.yaml '
            'of myapp.',
          ),
        ),
        environment: _environment,
      );
      expect(_experimentsByPackage(_readPackageConfig()), {
        'bar': ['foo.new_api'],
        'myapp': ['foo.new_api'],
      });

      // A dependency that only lists graduated/retired package experiments does
      // not require the root package to opt in.
      server.serve(
        'baz',
        '1.0.0',
        deps: {'foo': '^1.0.0'},
        pubspec: {
          'experiments': {
            'enable': ['foo.graduated_api', 'foo.retired_api'],
          },
        },
      );
      await d.appDir(dependencies: {'baz': '^1.0.0'}).create();
      await pubGet(
        output: allOf(
          contains('+ baz 1.0.0'),
          isNot(contains('Experiments enabled')),
        ),
        environment: _environment,
      );
      expect(_experimentsByPackage(_readPackageConfig()), isEmpty);
    },
  );

  test('selects version where package experiment has graduated, or fails if '
      'constrained to ungraduated version without opt-in', () async {
    final server = await servePackages();
    await _setupSdks();
    server.serve(
      'foo',
      '0.8.0',
      pubspec: {
        'experiments': {
          'declare': {
            'graduated_api': {'description': 'Experimental in 0.8.0'},
          },
        },
      },
    );
    server.serve(
      'foo',
      '1.0.0',
      pubspec: {
        'experiments': {
          'declare': {
            'graduated_api': {
              'description': 'Graduated in 0.9.0',
              'enabledIn': '0.9.0',
            },
          },
        },
      },
    );
    server.serve(
      'bar',
      '1.0.0-dev',
      deps: {'foo': '>=0.8.0 <2.0.0'},
      pubspec: {
        'experiments': {
          'enable': ['foo.graduated_api'],
        },
      },
    );

    // When `myapp` pins `foo: 0.8.0` without opting in to
    // `foo.graduated_api`, solving fails with the experiment hint.
    await d
        .appDir(dependencies: {'bar': '^1.0.0-dev', 'foo': '0.8.0'})
        .create();
    await pubGet(
      error: contains(
        'The experiment `foo.graduated_api` has not been enabled.',
      ),
      environment: _environment,
    );

    // When `myapp` allows `foo: ^1.0.0` (where `graduated_api` is graduated),
    // solving succeeds without opt-in.
    await d
        .appDir(dependencies: {'bar': '^1.0.0-dev', 'foo': '>=0.8.0 <2.0.0'})
        .create();
    await pubGet(output: contains('+ foo 1.0.0'), environment: _environment);
    expect(_experimentsByPackage(_readPackageConfig()), isEmpty);
  });

  test('supports intra-workspace declared experiments', () async {
    await servePackages();
    await _setupSdks();
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
            resolutionWorkspace: true,
            extras: {
              'experiments': {
                'declare': {
                  'exp_one': {'description': 'Workspace experiment one'},
                  'exp_graduated': {
                    'description': 'Graduated workspace experiment',
                    'enabledIn': '1.0.0',
                  },
                },
              },
            },
          ),
        ]),
        d.dir('b', [
          d.libPubspec(
            'b',
            '1.0.0',
            deps: {'a': '^1.0.0'},
            resolutionWorkspace: true,
            extras: {
              'experiments': {
                'enable': ['a.exp_one', 'a.exp_graduated'],
              },
            },
          ),
        ]),
      ]),
    ]).create();

    await pubGet(
      output: contains('* `a.exp_one` for b - Workspace experiment one'),
      warning: contains(
        'The experiment `a.exp_graduated` has been enabled by default since a '
        '1.0.0. Remove it from `experiments` in the pubspec.yaml of b.',
      ),
      environment: {..._environment, '_PUB_TEST_SDK_VERSION': '3.5.0'},
    );
    expect(_experimentsByPackage(_readPackageConfig()), {
      'b': ['a.exp_one'],
    });
  });

  test(
    'errors when a package-scoped experiment references a missing package or '
    'undeclared experiment',
    () async {
      final server = await servePackages();
      await _setupSdks();
      server.serve(
        'foo',
        '1.0.0',
        pubspec: {
          'experiments': {
            'declare': {
              'new_api': {
                'description': 'New experimental API',
                'docUrl': 'https://example.com/new_api',
              },
            },
          },
        },
      );
      server.serve('plain_pkg', '1.0.0');

      await d
          .appDir(
            pubspec: {
              'experiments': {
                'enable': ['missing_pkg.new_api'],
              },
            },
          )
          .create();
      await pubGet(
        error: contains(
          'The experiment `missing_pkg.new_api` in the pubspec.yaml of myapp '
          'refers to package `missing_pkg`, which is not in the dependency '
          'graph.',
        ),
        environment: _environment,
        exitCode: DATA,
      );

      await d
          .appDir(
            dependencies: {'foo': '^1.0.0'},
            pubspec: {
              'experiments': {
                'enable': ['foo.unknown_api'],
              },
            },
          )
          .create();
      await pubGet(
        error: contains(
          '`foo.unknown_api` is not a known experiment of package `foo` '
          '(1.0.0).\n\n'
          'Available experiments in `foo` (1.0.0) are:\n'
          '* `foo.new_api`: New experimental API (https://example.com/new_api)',
        ),
        environment: _environment,
        exitCode: DATA,
      );

      await d
          .appDir(
            dependencies: {'plain_pkg': '^1.0.0'},
            pubspec: {
              'experiments': {
                'enable': ['plain_pkg.some_api'],
              },
            },
          )
          .create();
      await pubGet(
        error: contains(
          '`plain_pkg.some_api` is not a known experiment of package '
          '`plain_pkg` (1.0.0).\n\n'
          'Package `plain_pkg` (1.0.0) does not declare any experiments.',
        ),
        environment: _environment,
        exitCode: DATA,
      );
    },
  );

  test(
    'rejects malformed package-scoped experiment names and declare schema',
    () async {
      await _setupSdks();
      for (final bad in ['no-foo.bar', 'foo.', '.bar', 'foo.bar.baz']) {
        await d
            .appDir(
              pubspec: {
                'experiments': {
                  'enable': [bad],
                },
              },
            )
            .create();
        await pubGet(
          error: contains(
            'Package experiment `$bad` must have the form '
            '`<package>.<experiment>`.',
          ),
          environment: _environment,
          exitCode: DATA,
        );
      }

      for (final badDeclared in ['no-exp', 'foo.bar']) {
        await d
            .appDir(
              pubspec: {
                'experiments': {
                  'declare': {
                    badDeclared: {'description': 'Bad name'},
                  },
                },
              },
            )
            .create();
        await pubGet(
          error: contains(
            'Declared experiment name must be a valid identifier '
            '(matching `^[a-zA-Z0-9_-]+\$` and not starting with `no-`).',
          ),
          environment: _environment,
          exitCode: DATA,
        );
      }

      final invalidSchemas = <(Object, String)>[
        (
          <String>['abc'],
          '`experiments` must be a mapping with `enable` and/or `declare` '
              'keys.',
        ),
        (
          123,
          '`experiments` must be a mapping with `enable` and/or `declare` '
              'keys.',
        ),
        (
          {'unknown': <String>[]},
          '`experiments` mapping may only contain `enable` and `declare` keys.',
        ),
        (
          {'enable': 'not-a-list'},
          '`experiments.enable` must be a list of strings',
        ),
        (
          {
            'enable': [123],
          },
          '`experiments.enable` must be a list of strings',
        ),
        ({'declare': <String>[]}, '`experiments.declare` must be a mapping'),
        (
          {
            'declare': {'exp': 'not-a-map'},
          },
          'Declared experiment `exp` must be a mapping.',
        ),
        (
          {
            'declare': {
              'exp': {'description': 'ok', 'bogus': 1},
            },
          },
          'Unknown field `bogus` in declared experiment `exp`.',
        ),
        (
          {
            'declare': {'exp': <String, Object?>{}},
          },
          'Declared experiment `exp` must have a string "description".',
        ),
        (
          {
            'declare': {
              'exp': {'description': 'ok', 'docUrl': 123},
            },
          },
          '"docUrl" of declared experiment `exp` must be a string.',
        ),
        (
          {
            'declare': {
              'exp': {'description': 'ok', 'enabledIn': 123},
            },
          },
          '"enabledIn" of declared experiment `exp` must be a version string.',
        ),
        (
          {
            'declare': {
              'exp': {'description': 'ok', 'enabledIn': 'not-a-version'},
            },
          },
          'Invalid "enabledIn" version in declared experiment `exp`:',
        ),
        (
          {
            'declare': {
              'exp': {'description': 'ok', 'expired': 'not-a-bool'},
            },
          },
          '"expired" of declared experiment `exp` must be a boolean.',
        ),
      ];

      for (final (schema, expectedError) in invalidSchemas) {
        await d.appDir(pubspec: {'experiments': schema}).create();
        await pubGet(
          error: contains(expectedError),
          environment: _environment,
          exitCode: DATA,
        );
      }
    },
  );

  test(
    'solver error reporting handles multiple disallowed experiments, '
    'channel-restricted experiments, and already-enabled experiments',
    () async {
      final server = await servePackages();
      await _setupSdks(
        dartExperiments: [
          {'name': 'def', 'description': 'Second experiment'},
          {'name': 'ghi', 'description': 'Third experiment'},
        ],
      );

      // 1. Dependency requires multiple disallowed experiments (`def`, `ghi`)
      // while root already has `abc` enabled.
      server.serve(
        'foo',
        '1.0.0-dev',
        pubspec: {
          'experiments': {
            'enable': ['def', 'ghi'],
          },
        },
      );
      await d
          .appDir(
            dependencies: {'foo': '^1.0.0-dev'},
            pubspec: {
              'experiments': {
                'enable': ['abc'],
              },
            },
          )
          .create();
      await pubGet(
        error: '''
Because myapp depends on foo any which requires enabling the experiments `def`, `ghi`, version solving failed.

The experiments `def`, `ghi` have not been enabled.

Currently the following experiments are enabled: `abc`.

To enable them add to your pubspec.yaml:

```
experiments:
  enable:
    - abc
    - def
    - ghi
```

Read more about experiments at https://dart.dev/go/experiments.''',
        environment: _environment,
      );

      // 2. Dependency requires an experiment (`main-only`) that is unavailable
      // on the current SDK channel (`stable`).
      server.serve(
        'bar',
        '1.0.0-dev',
        pubspec: {
          'experiments': {
            'enable': ['main-only'],
          },
        },
      );
      await d.appDir(dependencies: {'bar': '^1.0.0-dev'}).create();
      await pubGet(
        error: '''
Because myapp depends on bar any which requires enabling the experiment `main-only`, version solving failed.

The experiment `main-only` is only available on the main channel(s). This SDK is on the stable channel.

Read more about experiments at https://dart.dev/go/experiments.''',
        environment: {..._environment, '_PUB_TEST_SDK_CHANNEL': 'stable'},
      );
    },
  );
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
