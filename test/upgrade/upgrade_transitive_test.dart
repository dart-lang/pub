// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test(
    'without --unlock-transitive, the transitive dependencies stay locked',
    () async {
      final server = await servePackages();
      server.serve('foo', '1.0.0', deps: {'bar': '^1.0.0'});
      server.serve('bar', '1.0.0');

      await d.appDir(dependencies: {'foo': '^1.0.0'}).create();

      await pubGet(output: contains('+ foo 1.0.0'));

      server.serve('foo', '1.5.0', deps: {'bar': '^1.0.0'});
      server.serve('bar', '1.5.0');

      await pubUpgrade(
        args: ['foo'],
        output: allOf(contains('> foo 1.5.0'), isNot(contains('> bar'))),
      );
    },
  );

  test('`--unlock-transitive` dependencies gets unlocked', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0', deps: {'bar': '^1.0.0'});
    server.serve('bar', '1.0.0');
    server.serve('baz', '1.0.0');

    await d.appDir(dependencies: {'foo': '^1.0.0', 'baz': '^1.0.0'}).create();

    await pubGet(output: contains('+ foo 1.0.0'));

    server.serve('foo', '1.5.0', deps: {'bar': '^1.0.0'});
    server.serve('bar', '1.5.0');
    server.serve('baz', '1.5.0');

    await pubUpgrade(
      args: ['--unlock-transitive', 'foo'],
      output: allOf(
        contains('> foo 1.5.0'),
        contains('> bar 1.5.0'),
        isNot(
          contains('baz 1.5.0'),
        ), // Baz is not a transitive dependency of bar
      ),
    );
  });

  test(
    '`--major-versions` without `--unlock-transitive` does not allow '
    'transitive dependencies to be upgraded along with the named packages',
    () async {
      final server = await servePackages();
      server.serve('foo', '1.0.0', deps: {'bar': '^1.0.0'});
      server.serve('bar', '1.0.0');

      await d.appDir(dependencies: {'foo': '^1.0.0'}).create();

      await pubGet(output: contains('+ foo 1.0.0'));

      server.serve('foo', '2.0.0', deps: {'bar': '^1.0.0'});
      server.serve('bar', '1.5.0');

      await pubUpgrade(
        args: ['--major-versions', 'foo'],
        output: allOf(contains('> foo 2.0.0'), isNot(contains('bar 1.5.0'))),
      );
    },
  );

  test(
    '`--major-versions` rejects transitive dependency targets with suffixes',
    () async {
      final server = await servePackages();
      server.serve('foo', '1.0.0', deps: {'bar': '^1.0.0'});
      server.serve('bar', '1.0.0');

      await d.appDir(dependencies: {'foo': '^1.0.0'}).create();

      await pubGet(output: contains('+ foo 1.0.0'));

      await pubUpgrade(
        args: ['--major-versions', 'bar@^2.0.0'],
        error: allOf(
          contains(
            'Dependencies specified in `dart pub upgrade --major-versions '
            '<dependencies>`',
          ),
          contains('be direct'),
          contains(' - bar'),
        ),
        exitCode: exit_codes.USAGE,
      );
    },
  );

  test('`--unlock-transitive --major-versions` allows transitive dependencies '
      'be upgraded along with the named packages', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0', deps: {'bar': '^1.0.0'});
    server.serve('bar', '1.0.0');
    server.serve('baz', '1.0.0');

    await d.appDir(dependencies: {'foo': '^1.0.0', 'baz': '^1.0.0'}).create();

    await pubGet(output: contains('+ foo 1.0.0'));

    server.serve('foo', '2.0.0', deps: {'bar': '^1.0.0'});
    server.serve('bar', '1.5.0');
    server.serve('baz', '1.5.0');

    await pubUpgrade(
      args: ['--major-versions', '--unlock-transitive', 'foo'],
      output: allOf(
        contains('> foo 2.0.0'),
        contains('> bar 1.5.0'),
        isNot(contains('> baz 1.5.0')),
      ),
    );
  });

  test('`dependency@latest` explains why latest cannot be selected', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0', deps: {'bar': '^1.0.0'});
    server.serve('bar', '1.0.0');

    await d.appDir(dependencies: {'foo': '^1.0.0'}).create();

    await pubGet(output: contains('+ foo 1.0.0'));

    server.serve('bar', '2.0.0');

    await pubUpgrade(
      args: ['bar@latest'],
      error: allOf(
        contains('bar 2.0.0'),
        contains('bar@latest'),
        contains('foo'),
        contains('bar ^1.0.0'),
        contains('version solving failed'),
      ),
    );
  });

  test(
    '`dependency@latest` upgrades a transitive dependency to latest',
    () async {
      final server = await servePackages();
      server.serve('foo', '1.0.0', deps: {'bar': 'any'});
      server.serve('bar', '1.0.0');

      await d.appDir(dependencies: {'foo': '^1.0.0'}).create();

      await pubGet(output: contains('+ foo 1.0.0'));

      server.serve('bar', '2.0.0');

      await pubUpgrade(args: ['bar@latest'], output: contains('> bar 2.0.0'));
    },
  );

  test('`dependency@resolvable` upgrades a transitive dependency to latest '
      'resolvable', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0', deps: {'bar': '^1.0.0'});
    server.serve('bar', '1.0.0');

    await d.appDir(dependencies: {'foo': '^1.0.0'}).create();

    await pubGet(output: contains('+ foo 1.0.0'));

    server.serve('bar', '1.5.0');
    server.serve('bar', '2.0.0');

    await pubUpgrade(
      args: ['bar@resolvable'],
      output: allOf(contains('> bar 1.5.0'), isNot(contains('bar 2.0.0'))),
    );
  });

  test(
    '`dependency@version` upgrades a transitive dependency to that version',
    () async {
      final server = await servePackages();
      server.serve('foo', '1.0.0', deps: {'bar': 'any'});
      server.serve('bar', '1.0.0');

      await d.appDir(dependencies: {'foo': '^1.0.0'}).create();

      await pubGet(output: contains('+ foo 1.0.0'));

      server.serve('bar', '1.5.0');
      server.serve('bar', '2.0.0');

      await pubUpgrade(
        args: ['bar@1.5.0'],
        output: allOf(contains('> bar 1.5.0'), isNot(contains('bar 2.0.0'))),
      );
    },
  );

  test('`dependency@version` can target a pre-release version', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0', deps: {'bar': 'any'});
    server.serve('bar', '1.0.0');

    await d.appDir(dependencies: {'foo': '^1.0.0'}).create();

    await pubGet(output: contains('+ foo 1.0.0'));

    server.serve('bar', '1.5.0-beta');
    server.serve('bar', '2.0.0');

    await pubUpgrade(
      args: ['bar@1.5.0-beta'],
      output: allOf(contains('> bar 1.5.0-beta'), isNot(contains('bar 2.0.0'))),
    );
  });

  test(
    '`dependency@version` explains why that version cannot be selected',
    () async {
      final server = await servePackages();
      server.serve('foo', '1.0.0', deps: {'bar': '^1.0.0'});
      server.serve('bar', '1.0.0');

      await d.appDir(dependencies: {'foo': '^1.0.0'}).create();

      await pubGet(output: contains('+ foo 1.0.0'));

      server.serve('bar', '2.0.0');

      await pubUpgrade(
        args: ['bar@2.0.0'],
        error: allOf(
          contains('bar 2.0.0'),
          contains('bar@2.0.0'),
          contains('foo'),
          contains('bar ^1.0.0'),
          contains('version solving failed'),
        ),
      );
    },
  );

  test(
    '`dependency@resolvable` explains why resolvable cannot be selected',
    () async {
      final server = await servePackages();
      server.serve('foo', '1.0.0', deps: {'bar': '^1.0.0'});
      server.serve('foo', '2.0.0', deps: {'bar': '^2.0.0'});
      server.serve('bar', '1.0.0');

      await d.appDir(dependencies: {'foo': '^1.0.0'}).create();

      await pubGet(output: contains('+ foo 1.0.0'));

      server.serve('bar', '2.0.0');

      await pubUpgrade(
        args: ['bar@resolvable'],
        error: allOf(
          contains('bar 2.0.0'),
          contains('bar@resolvable'),
          contains('foo'),
          contains('bar ^1.0.0'),
          contains('version solving failed'),
        ),
      );
    },
  );

  test('multiple dependency targets resolve together', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0', deps: {'bar': 'any', 'baz': '^1.0.0'});
    server.serve('bar', '1.0.0');
    server.serve('baz', '1.0.0');

    await d.appDir(dependencies: {'foo': '^1.0.0'}).create();

    await pubGet(output: contains('+ foo 1.0.0'));

    server.serve('foo', '1.5.0', deps: {'bar': 'any', 'baz': '^1.0.0'});
    server.serve('bar', '2.0.0');
    server.serve('baz', '1.5.0');
    server.serve('baz', '2.0.0');

    await pubUpgrade(
      args: ['foo', 'bar@latest', 'baz@resolvable'],
      output: allOf(
        contains('> foo 1.5.0'),
        contains('> bar 2.0.0'),
        contains('> baz 1.5.0'),
        isNot(contains('baz 2.0.0')),
      ),
    );
  });

  test('`dependency@resolvable` honors other target constraints', () async {
    final server = await servePackages();
    server.serve('bar', '1.0.0', deps: {'baz': '<2.0.0'});
    server.serve('baz', '1.0.0');

    await d.appDir(dependencies: {'bar': 'any', 'baz': 'any'}).create();

    await pubGet(output: contains('+ bar 1.0.0'));

    server.serve('bar', '2.0.0', deps: {'baz': '^2.0.0'});
    server.serve('baz', '1.5.0');
    server.serve('baz', '2.0.0');

    await pubUpgrade(
      args: ['bar@1.0.0', 'baz@resolvable'],
      output: allOf(contains('> baz 1.5.0'), isNot(contains('baz 2.0.0'))),
    );
  });

  test('`dependency@latest` is resolved separately for examples', () async {
    final server = await servePackages();
    server.serve('bar', '1.0.0');

    await d.dir(appPath, [
      d.appPubspec(dependencies: {'bar': '^1.0.0'}),
      d.dir('bar', [d.libPubspec('bar', '2.0.0'), d.libDir('bar')]),
      d.dir('example', [
        d.pubspec({
          'name': 'app_example',
          'dependencies': {
            'bar': {'path': '../bar'},
          },
        }),
      ]),
    ]).create();

    await pubGet(args: ['--example']);

    server.serve('bar', '1.5.0');

    await pubUpgrade(
      args: ['--example', 'bar@latest'],
      output: contains('> bar 1.5.0'),
    );

    await d.dir(appPath, [
      d.dir('example', [
        d.file(
          'pubspec.lock',
          allOf(contains('source: path'), contains('version: "2.0.0"')),
        ),
      ]),
    ]).validate();
  });

  test('`dependency@latest` can target an example-only dependency', () async {
    final server = await servePackages();
    server.serve('bar', '1.0.0');

    await d.dir(appPath, [
      d.appPubspec(),
      d.dir('example', [
        d.pubspec({
          'name': 'app_example',
          'dependencies': {'bar': 'any'},
        }),
      ]),
    ]).create();

    await pubGet(args: ['--example']);

    server.serve('bar', '2.0.0');

    await pubUpgrade(
      args: ['--example', 'bar@latest'],
      output: contains('Got dependencies in'),
    );

    await d.dir(appPath, [
      d.dir('example', [
        d.file(
          'pubspec.lock',
          allOf(contains('source: hosted'), contains('version: "2.0.0"')),
        ),
      ]),
    ]).validate();
  });

  test('`--unlock-transitive` can target an example-only dependency', () async {
    final server = await servePackages();
    server.serve('root_dep', '1.0.0');
    server.serve('foo', '1.0.0', deps: {'bar': '^1.0.0'});
    server.serve('bar', '1.0.0');

    await d.dir(appPath, [
      d.appPubspec(dependencies: {'root_dep': 'any'}),
      d.dir('example', [
        d.pubspec({
          'name': 'app_example',
          'dependencies': {'foo': 'any'},
        }),
      ]),
    ]).create();

    await pubGet(args: ['--example']);

    server.serve('root_dep', '2.0.0');
    server.serve('foo', '1.5.0', deps: {'bar': '^1.0.0'});
    server.serve('bar', '1.5.0');

    await pubUpgrade(
      args: ['--example', '--unlock-transitive', 'foo@latest'],
      output: contains('Got dependencies in'),
    );

    await d.dir(appPath, [
      d.file(
        'pubspec.lock',
        allOf(contains('root_dep:'), contains('version: "1.0.0"')),
      ),
      d.dir('example', [
        d.file(
          'pubspec.lock',
          allOf(
            matches(RegExp(r'bar:[\s\S]*version: "1\.5\.0"')),
            matches(RegExp(r'foo:[\s\S]*version: "1\.5\.0"')),
          ),
        ),
      ]),
    ]).validate();
  });

  test('`--unlock-transitive` does not unlock unrelated examples', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');
    server.serve('example_dep', '1.0.0');

    await d.dir(appPath, [
      d.appPubspec(dependencies: {'foo': 'any'}),
      d.dir('example', [
        d.pubspec({
          'name': 'app_example',
          'dependencies': {'example_dep': 'any'},
        }),
      ]),
    ]).create();

    await pubGet(args: ['--example']);

    server.serve('foo', '1.5.0');
    server.serve('example_dep', '2.0.0');

    await pubUpgrade(
      args: ['--example', '--unlock-transitive', 'foo@latest'],
      output: allOf(contains('> foo 1.5.0'), contains('Got dependencies in')),
    );

    await d.dir(appPath, [
      d.dir('example', [
        d.file(
          'pubspec.lock',
          allOf(contains('example_dep:'), contains('version: "1.0.0"')),
        ),
      ]),
    ]).validate();
  });

  test(
    '`--unlock-transitive` rejects unknown packages in mixed targets',
    () async {
      final server = await servePackages();
      server.serve('foo', '1.0.0', deps: {'bar': '^1.0.0'});
      server.serve('bar', '1.0.0');

      await d.appDir(dependencies: {'foo': '^1.0.0'}).create();

      await pubGet(output: contains('+ foo 1.0.0'));

      await pubUpgrade(
        args: ['--no-example', '--unlock-transitive', 'foo', 'missing'],
        error: allOf(
          contains('Package `missing` is not in the current resolution.'),
          contains('It was not found in the root package.'),
        ),
        exitCode: exit_codes.DATA,
      );
    },
  );

  test('`dependency@latest` uses the dependency source from pubspec', () async {
    final server = await servePackages();
    server.serve('bar', '1.0.0');
    server.serve('bar', '1.5.0');

    await d.dir('bar', [
      d.libPubspec('bar', '2.0.0'),
      d.libDir('bar'),
    ]).create();

    await d.appDir(dependencies: {'bar': '^1.0.0'}).create();

    await pubGet(output: contains('+ bar 1.5.0'));

    await d
        .appDir(
          dependencies: {
            'bar': {'path': '../bar'},
          },
        )
        .create();

    await pubUpgrade(
      args: ['bar@latest'],
      output: contains('* bar 2.0.0 from path'),
    );

    await d.dir(appPath, [
      d.file(
        'pubspec.lock',
        allOf(contains('source: path'), contains('version: "2.0.0"')),
      ),
    ]).validate();
  });

  test('`dependency@latest` uses the dependency override source', () async {
    final server = await servePackages();
    server.serve('bar', '1.0.0');
    server.serve('bar', '2.0.0');

    await d.dir('bar', [
      d.libPubspec('bar', '3.0.0'),
      d.libDir('bar'),
    ]).create();

    await d
        .appDir(
          dependencies: {'bar': 'any'},
          pubspec: {
            'dependency_overrides': {
              'bar': {'path': '../bar'},
            },
          },
        )
        .create();

    await pubGet();

    await pubUpgrade(
      args: ['bar@latest'],
      output: contains('No dependencies changed.'),
    );

    await d.dir(appPath, [
      d.file(
        'pubspec.lock',
        allOf(contains('source: path'), contains('version: "3.0.0"')),
      ),
    ]).validate();
  });

  test(
    '`dependency@latest` requires a package from the current resolution',
    () async {
      await servePackages();
      await d.appDir(dependencies: {'foo': '^1.0.0'}).create();

      await pubUpgrade(
        args: ['missing@latest'],
        error: contains('Package `missing` is not in the current resolution.'),
        exitCode: exit_codes.DATA,
      );
    },
  );

  test('`dependency@latest` requires a package from the current resolution '
      'with examples', () async {
    await servePackages();
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir('example', [
        d.pubspec({'name': 'app_example'}),
      ]),
    ]).create();

    await pubUpgrade(
      args: ['--example', 'missing@latest'],
      error: allOf(
        contains('Package `missing` is not in the current resolution.'),
        contains('It was not found in the root package or any examples.'),
      ),
      exitCode: exit_codes.DATA,
    );
  });

  test(
    '`dependency@constraint` can be combined with --major-versions',
    () async {
      final server = await servePackages();
      server.serve('bar', '1.0.0');

      await d.appDir(dependencies: {'bar': '^1.0.0'}).create();

      await pubGet();

      server.serve('bar', '2.0.0');
      server.serve('bar', '3.0.0');

      await pubUpgrade(
        args: ['--major-versions', 'bar@^2.0.0'],
        output: contains('> bar 2.0.0'),
      );

      await d.appDir(dependencies: {'bar': '^2.0.0'}).validate();
    },
  );

  test(
    '`dependency@constraint` constrains the final --major-versions solve',
    () async {
      final server = await servePackages();
      server.serve('foo', '1.0.0');

      await d.appDir(dependencies: {'foo': '^1.0.0'}).create();

      await pubGet();

      server.serve('foo', '1.5.0');
      server.serve('foo', '1.6.0');

      await pubUpgrade(
        args: ['--major-versions', 'foo@<=1.5.0'],
        output: allOf(contains('> foo 1.5.0'), isNot(contains('foo 1.6.0'))),
      );

      await d.dir(appPath, [
        d.file(
          'pubspec.lock',
          allOf(contains('version: "1.5.0"'), isNot(contains('1.6.0'))),
        ),
      ]).validate();
    },
  );

  test('`dependency@latest` can be combined with --major-versions', () async {
    final server = await servePackages();
    server.serve('bar', '1.0.0');

    await d.appDir(dependencies: {'bar': '^1.0.0'}).create();

    await pubGet();

    server.serve('bar', '1.5.0');
    server.serve('bar', '2.0.0');
    server.serve('bar', '3.0.0');

    await pubUpgrade(
      args: ['--major-versions', 'bar@latest'],
      output: contains('> bar 3.0.0'),
    );

    await d.appDir(dependencies: {'bar': '^3.0.0'}).validate();
  });

  test(
    '`dependency@resolvable` can be combined with --major-versions',
    () async {
      final server = await servePackages();
      server.serve('bar', '1.0.0', deps: {'baz': '^1.0.0'});
      server.serve('baz', '1.0.0');
      server.serve('qux', '1.0.0', deps: {'baz': '^1.0.0'});

      await d.appDir(dependencies: {'bar': '^1.0.0', 'qux': '^1.0.0'}).create();

      await pubGet();

      server.serve('bar', '2.0.0', deps: {'baz': '^1.0.0'});
      server.serve('bar', '3.0.0', deps: {'baz': '^2.0.0'});
      server.serve('baz', '2.0.0');

      await pubUpgrade(
        args: ['--major-versions', 'bar@resolvable'],
        output: allOf(contains('> bar 2.0.0'), isNot(contains('bar 3.0.0'))),
      );

      await d
          .appDir(dependencies: {'bar': '^2.0.0', 'qux': '^1.0.0'})
          .validate();
    },
  );

  test('`dependency@constraint` can be combined with --tighten', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');

    await d.appDir(dependencies: {'foo': 'any'}).create();

    await pubGet();

    server.serve('foo', '1.5.0');
    server.serve('foo', '2.0.0');

    await pubUpgrade(
      args: ['--tighten', 'foo@<2.0.0'],
      output: allOf(contains('> foo 1.5.0'), isNot(contains('foo 2.0.0'))),
    );

    await d.appDir(dependencies: {'foo': '^1.5.0'}).validate();
  });

  test('`dependency@latest` can be combined with --tighten', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');

    await d.appDir(dependencies: {'foo': '>=1.0.0 <3.0.0'}).create();

    await pubGet();

    server.serve('foo', '1.5.0');
    server.serve('foo', '2.0.0');

    await pubUpgrade(
      args: ['--tighten', 'foo@latest'],
      output: contains('> foo 2.0.0'),
    );

    await d.appDir(dependencies: {'foo': '^2.0.0'}).validate();
  });

  test('`dependency@resolvable` can be combined with --tighten', () async {
    final server = await servePackages();
    server.serve('bar', '1.0.0', deps: {'baz': '^1.0.0'});
    server.serve('baz', '1.0.0');
    server.serve('qux', '1.0.0', deps: {'baz': '^1.0.0'});

    await d
        .appDir(dependencies: {'bar': '>=1.0.0 <3.0.0', 'qux': '^1.0.0'})
        .create();

    await pubGet();

    server.serve('bar', '2.0.0', deps: {'baz': '^1.0.0'});
    server.serve('bar', '3.0.0', deps: {'baz': '^2.0.0'});
    server.serve('baz', '2.0.0');

    await pubUpgrade(
      args: ['--tighten', 'bar@resolvable'],
      output: allOf(contains('> bar 2.0.0'), isNot(contains('bar 3.0.0'))),
    );

    await d.appDir(dependencies: {'bar': '^2.0.0', 'qux': '^1.0.0'}).validate();
  });

  test('dependency target uses @ instead of colon', () async {
    await servePackages();
    await d.appDir(dependencies: {'foo': '^1.0.0'}).create();

    for (final target in [
      'foo:latest',
      'foo:resolvable',
      'foo_bar:latest',
      'foo_bar:resolvable',
    ]) {
      await pubUpgrade(
        args: [target],
        error: allOf(
          contains('Unknown upgrade target `$target`.'),
          contains('Use `<package>`'),
          contains('`<package>@<constraint>`'),
          contains('`<package>@latest`'),
          contains('`<package>@resolvable`.'),
        ),
        exitCode: exit_codes.USAGE,
      );
    }
  });

  test('dependency target requires a valid suffix after @', () async {
    await servePackages();
    await d.appDir(dependencies: {'foo': '^1.0.0'}).create();

    for (final target in ['foo@', 'foo@Latest', 'foo@not-a-version']) {
      await pubUpgrade(
        args: [target],
        error: allOf(
          contains('Unknown upgrade target `$target`.'),
          contains('Use `<package>`'),
          contains('`<package>@<constraint>`'),
          contains('`<package>@latest`'),
          contains('`<package>@resolvable`.'),
        ),
        exitCode: exit_codes.USAGE,
      );
    }
  });

  test('dependency target cannot contain multiple @ separators', () async {
    await servePackages();
    await d.appDir(dependencies: {'foo': '^1.0.0'}).create();

    await pubUpgrade(
      args: ['foo@bar@latest'],
      error: allOf(
        contains('Could not parse upgrade target `foo@bar@latest`.'),
        contains('Use `<package>`'),
        contains('`<package>@<constraint>`'),
        contains('`<package>@latest`'),
        contains('`<package>@resolvable`.'),
      ),
      exitCode: exit_codes.USAGE,
    );
  });

  test('`dependency@constraint` upgrades a transitive dependency '
      'with a constraint', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0', deps: {'bar': 'any'});
    server.serve('bar', '1.0.0');

    await d.appDir(dependencies: {'foo': '^1.0.0'}).create();

    await pubGet(output: contains('+ foo 1.0.0'));

    server.serve('bar', '1.1.0');
    server.serve('bar', '1.5.0');
    server.serve('bar', '2.0.0');

    // Upgrades to 1.5.0 because it's the latest satisfying <2.0.0
    await pubUpgrade(
      args: ['bar@<2.0.0'],
      output: allOf(contains('> bar 1.5.0'), isNot(contains('bar 2.0.0'))),
    );
  });

  test('`dependency@constraint` suggests --major-versions when blocked by '
      'the root constraint', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');

    await d.appDir(dependencies: {'foo': '^1.0.0'}).create();

    await pubGet(
      workingDirectory: d.sandbox,
      args: ['--directory', appPath],
      output: contains('+ foo 1.0.0'),
    );

    server.serve('foo', '2.0.0');

    final suggestedArgs = [
      '--major-versions',
      '--tighten',
      '--directory',
      appPath,
      'foo@2.0.0',
    ];

    await pubUpgrade(
      workingDirectory: d.sandbox,
      args: ['--tighten', '--directory', appPath, 'foo@2.0.0'],
      error: allOf(
        contains('The requested constraint `2.0.0` for `foo`'),
        contains('current constraint `^1.0.0`'),
        contains('pubspec.yaml'),
        contains(['dart', 'pub', 'upgrade', ...suggestedArgs].join(' ')),
        isNot(contains('version solving failed')),
      ),
      exitCode: exit_codes.DATA,
    );

    await pubUpgrade(
      workingDirectory: d.sandbox,
      args: suggestedArgs,
      output: contains('> foo 2.0.0'),
    );

    await d.appDir(dependencies: {'foo': '^2.0.0'}).validate();
  });

  test(
    '`dependency@constraint` allows overlap with the root constraint',
    () async {
      final server = await servePackages();
      server.serve('foo', '1.0.0');

      await d.appDir(dependencies: {'foo': '>=1.0.0 <3.0.0'}).create();

      await pubGet(output: contains('+ foo 1.0.0'));

      server.serve('foo', '2.0.0');

      await pubUpgrade(args: ['foo@2.0.0'], output: contains('> foo 2.0.0'));
    },
  );

  test('`dependency@constraint` suggests --major-versions when blocked by '
      'a workspace constraint', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');

    await d.dir(appPath, [
      d.libPubspec(
        'myapp',
        '1.0.0',
        sdk: '^3.5.0',
        extras: {
          'workspace': ['a'],
        },
      ),
      d.dir('a', [
        d.libPubspec(
          'a',
          '1.0.0',
          deps: {'foo': '^1.0.0'},
          resolutionWorkspace: true,
        ),
      ]),
    ]).create();

    await pubGet(
      workingDirectory: d.sandbox,
      args: ['--directory', appPath],
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      output: contains('+ foo 1.0.0'),
    );

    server.serve('foo', '2.0.0');

    final suggestedArgs = [
      '--major-versions',
      '--directory',
      appPath,
      'foo@2.0.0',
    ];

    await pubUpgrade(
      workingDirectory: d.sandbox,
      args: ['--directory', appPath, 'foo@2.0.0'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      error: allOf(
        contains('The requested constraint `2.0.0` for `foo`'),
        contains('current constraint `^1.0.0`'),
        matches(RegExp(r'a[\\/]pubspec\.yaml')),
        contains(['dart', 'pub', 'upgrade', ...suggestedArgs].join(' ')),
      ),
      exitCode: exit_codes.DATA,
    );

    await pubUpgrade(
      workingDirectory: d.sandbox,
      args: suggestedArgs,
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      output: contains('> foo 2.0.0'),
    );

    await d.dir(appPath, [
      d.libPubspec(
        'myapp',
        '1.0.0',
        sdk: '^3.5.0',
        extras: {
          'workspace': ['a'],
        },
      ),
      d.dir('a', [
        d.libPubspec(
          'a',
          '1.0.0',
          deps: {'foo': '^2.0.0'},
          resolutionWorkspace: true,
        ),
      ]),
    ]).validate();
  });

  test('`dependency@constraint` does not suggest --major-versions for '
      'dependency override conflicts', () async {
    await servePackages();

    await d
        .appDir(
          dependencies: {'foo': 'any'},
          pubspec: {
            'dependency_overrides': {'foo': '1.0.0'},
          },
        )
        .create();

    await pubUpgrade(
      args: ['foo@2.0.0'],
      error: allOf(
        contains('The requested constraint `2.0.0` for `foo`'),
        contains('dependency override constraint `1.0.0`'),
        contains('Update or remove the dependency override before retrying.'),
        isNot(contains('--major-versions')),
      ),
      exitCode: exit_codes.DATA,
    );
  });
}
