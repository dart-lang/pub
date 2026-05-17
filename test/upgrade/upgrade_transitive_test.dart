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

  test('`dependency:latest` explains why latest cannot be selected', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0', deps: {'bar': '^1.0.0'});
    server.serve('bar', '1.0.0');

    await d.appDir(dependencies: {'foo': '^1.0.0'}).create();

    await pubGet(output: contains('+ foo 1.0.0'));

    server.serve('bar', '2.0.0');

    await pubUpgrade(
      args: ['bar:latest'],
      error: allOf(
        contains('bar 2.0.0'),
        contains('bar:latest'),
        contains('foo'),
        contains('bar ^1.0.0'),
        contains('version solving failed'),
      ),
    );
  });

  test(
    '`dependency:latest` upgrades a transitive dependency to latest',
    () async {
      final server = await servePackages();
      server.serve('foo', '1.0.0', deps: {'bar': 'any'});
      server.serve('bar', '1.0.0');

      await d.appDir(dependencies: {'foo': '^1.0.0'}).create();

      await pubGet(output: contains('+ foo 1.0.0'));

      server.serve('bar', '2.0.0');

      await pubUpgrade(args: ['bar:latest'], output: contains('> bar 2.0.0'));
    },
  );

  test('`dependency:resolvable` upgrades a transitive dependency to latest '
      'resolvable', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0', deps: {'bar': '^1.0.0'});
    server.serve('bar', '1.0.0');

    await d.appDir(dependencies: {'foo': '^1.0.0'}).create();

    await pubGet(output: contains('+ foo 1.0.0'));

    server.serve('bar', '1.5.0');
    server.serve('bar', '2.0.0');

    await pubUpgrade(
      args: ['bar:resolvable'],
      output: allOf(contains('> bar 1.5.0'), isNot(contains('bar 2.0.0'))),
    );
  });

  test(
    '`dependency:resolvable` explains why resolvable cannot be selected',
    () async {
      final server = await servePackages();
      server.serve('foo', '1.0.0', deps: {'bar': '^1.0.0'});
      server.serve('foo', '2.0.0', deps: {'bar': '^2.0.0'});
      server.serve('bar', '1.0.0');

      await d.appDir(dependencies: {'foo': '^1.0.0'}).create();

      await pubGet(output: contains('+ foo 1.0.0'));

      server.serve('bar', '2.0.0');

      await pubUpgrade(
        args: ['bar:resolvable'],
        error: allOf(
          contains('bar 2.0.0'),
          contains('bar:resolvable'),
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
      args: ['foo', 'bar:latest', 'baz:resolvable'],
      output: allOf(
        contains('> foo 1.5.0'),
        contains('> bar 2.0.0'),
        contains('> baz 1.5.0'),
        isNot(contains('baz 2.0.0')),
      ),
    );
  });

  test(
    '`dependency:latest` requires a package from the current resolution',
    () async {
      await servePackages();
      await d.appDir(dependencies: {'foo': '^1.0.0'}).create();

      await pubUpgrade(
        args: ['missing:latest'],
        error: contains('Package `missing` is not in the current resolution.'),
        exitCode: exit_codes.DATA,
      );
    },
  );

  test(
    '`dependency:latest` cannot be combined with --major-versions',
    () async {
      await servePackages();
      await d.appDir(dependencies: {'foo': '^1.0.0'}).create();

      await pubUpgrade(
        args: ['--major-versions', 'foo:latest'],
        error: contains(
          'Cannot use `:latest` or `:resolvable` with `--major-versions`.',
        ),
        exitCode: exit_codes.USAGE,
      );
    },
  );
}
