// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

Future<void> populateCache(
  Map<String, List<String>> versions,
  PackageServer server,
) async {
  for (final entry in versions.entries) {
    for (final version in entry.value) {
      server.serve(entry.key, version);
    }
  }
  for (final entry in versions.entries) {
    for (final version in entry.value) {
      await d.appDir(dependencies: {entry.key: version}).create();
      await pubGet();
    }
  }
}

void main() {
  forBothPubGetAndUpgrade((command) {
    test('upgrades a package using the cache', () async {
      final server = await servePackages();
      await populateCache(
        {
          'foo': ['1.2.2', '1.2.3'],
          'bar': ['1.2.3']
        },
        server,
      );

      // Now serve only errors - to validate we are truly offline.
      server.serveErrors();

      await d.appDir(dependencies: {'foo': 'any', 'bar': 'any'}).create();

      String? warning;
      if (command == RunCommand.upgrade) {
        warning = 'Warning: Upgrading when offline may not update you '
            'to the latest versions of your dependencies.';
      }

      await pubCommand(command, args: ['--offline'], warning: warning);
      await d.appPackageConfigFile([
        d.packageConfigEntry(name: 'foo', version: '1.2.3'),
        d.packageConfigEntry(name: 'bar', version: '1.2.3'),
      ]).validate();
    });

    test('supports prerelease versions', () async {
      final server = await servePackages();
      await populateCache(
        {
          'foo': ['1.2.3-alpha.1']
        },
        server,
      );
      // Now serve only errors - to validate we are truly offline.
      server.serveErrors();

      await d.appDir(dependencies: {'foo': 'any'}).create();

      String? warning;
      if (command == RunCommand.upgrade) {
        warning = 'Warning: Upgrading when offline may not update you '
            'to the latest versions of your dependencies.';
      }

      await pubCommand(command, args: ['--offline'], warning: warning);

      await d.appPackageConfigFile([
        d.packageConfigEntry(name: 'foo', version: '1.2.3-alpha.1'),
      ]).validate();
    });

    test('fails gracefully if a dependency is not cached', () async {
      // Run the server so that we know what URL to use in the system cache.
      final server = await servePackages();
      server.serveErrors();

      await d.appDir(dependencies: {'foo': 'any'}).create();

      await pubCommand(
        command,
        args: ['--offline'],
        exitCode: exit_codes.UNAVAILABLE,
        error: equalsIgnoringWhitespace("""
            Because myapp depends on foo any which doesn't exist (could not find
              package foo in cache), version solving failed.

            Try again without --offline!
          """),
      );
    });

    test('fails gracefully if no cached versions match', () async {
      final server = await servePackages();
      await populateCache(
        {
          'foo': ['1.2.2', '1.2.3']
        },
        server,
      );

      // Run the server so that we know what URL to use in the system cache.
      server.serveErrors();

      await d.appDir(dependencies: {'foo': '>2.0.0'}).create();

      await pubCommand(
        command,
        args: ['--offline'],
        error: equalsIgnoringWhitespace("""
            Because myapp depends on foo >2.0.0 which doesn't match any
              versions, version solving failed.
          """),
      );
    });

    test(
        'fails gracefully if a dependency is not cached and a lockfile '
        'exists', () async {
      final server = await servePackages();

      // Run the server so that we know what URL to use in the system cache.
      server.serveErrors();

      await d.appDir(dependencies: {'foo': 'any'}).create();

      await createLockFile('myapp', hosted: {'foo': '1.2.4'});

      await pubCommand(
        command,
        args: ['--offline'],
        exitCode: exit_codes.UNAVAILABLE,
        error: equalsIgnoringWhitespace("""
            Because myapp depends on foo any which doesn't exist (could not find
              package foo in cache), version solving failed.

            Try again without --offline!
          """),
      );
    });

    test('downgrades to the version in the cache if necessary', () async {
      final server = await servePackages();

      await populateCache(
        {
          'foo': ['1.2.2', '1.2.3']
        },
        server,
      );
      // Run the server so that we know what URL to use in the system cache.
      server.serveErrors();

      await d.appDir(dependencies: {'foo': 'any'}).create();

      await createLockFile('myapp', hosted: {'foo': '1.2.4'});

      await pubCommand(command, args: ['--offline']);

      await d.appPackageConfigFile([
        d.packageConfigEntry(name: 'foo', version: '1.2.3'),
      ]).validate();
    });

    test('skips invalid cached versions', () async {
      final server = await servePackages();

      await populateCache(
        {
          'foo': ['1.2.2', '1.2.3']
        },
        server,
      );
      // Run the server so that we know what URL to use in the system cache.
      server.serveErrors();

      await d.hostedCache([
        d.dir('foo-1.2.3', [d.file('pubspec.yaml', '{')]),
        d.file('random_filename', ''),
      ]).create();

      await d.appDir(dependencies: {'foo': 'any'}).create();

      await pubCommand(command, args: ['--offline']);

      await d.appPackageConfigFile([
        d.packageConfigEntry(name: 'foo', version: '1.2.2'),
      ]).validate();
    });

    test('skips invalid locked versions', () async {
      final server = await servePackages();

      await populateCache(
        {
          'foo': ['1.2.2', '1.2.3']
        },
        server,
      );
      // Run the server so that we know what URL to use in the system cache.
      server.serveErrors();

      await d.hostedCache([
        d.dir('foo-1.2.3', [d.file('pubspec.yaml', '{')])
      ]).create();

      await d.appDir(dependencies: {'foo': 'any'}).create();

      await createLockFile('myapp', hosted: {'foo': '1.2.3'});

      await pubCommand(command, args: ['--offline']);

      await d.appPackageConfigFile([
        d.packageConfigEntry(name: 'foo', version: '1.2.2'),
      ]).validate();
    });
  });
}
