// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;

import 'package:pub/src/io.dart';
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../hosted/offline_test.dart' show populateCache;
import '../../test_pub.dart';

void main() {
  test('Do not consider retracted packages', () async {
    final server = await servePackages()
      ..serve('foo', '1.0.0', deps: {'bar': '^1.0.0'})
      ..serve('bar', '1.0.0')
      ..serve('bar', '1.1.0');
    await d.appDir(dependencies: {'foo': '1.0.0'}).create();

    server.retractPackageVersion('bar', '1.1.0');
    await pubGet();

    await d.cacheDir({'foo': '1.0.0', 'bar': '1.0.0'}).validate();
    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '1.0.0'),
      d.packageConfigEntry(name: 'bar', version: '1.0.0'),
    ]).validate();
  });

  test('Error when the only available package version is retracted', () async {
    final server = await servePackages()
      ..serve('foo', '1.0.0', deps: {'bar': '^1.0.0'})
      ..serve('bar', '1.0.0');
    await d.appDir(dependencies: {'foo': '1.0.0'}).create();

    server.retractPackageVersion('bar', '1.0.0');
    await pubGet(
      error:
          '''Because every version of foo depends on bar ^1.0.0 which doesn't match any versions, foo is forbidden. 
            So, because myapp depends on foo 1.0.0, version solving failed.''',
    );
  });

  // Currently retraction does not affect prioritization. I.e., if
  // pubspec.lock already contains a retracted version, which is the newest
  // satisfying the dependency contstraint we will not choose to downgrade.
  // In this case we expect a newer version to be published at some point which
  // will then cause pub upgrade to choose that one.
  test('Allow retracted version when it was already in pubspec.lock', () async {
    final server = await servePackages()
      ..serve('foo', '1.0.0', deps: {'bar': '^1.0.0'})
      ..serve('bar', '1.0.0')
      ..serve('bar', '1.1.0');
    await d.appDir(dependencies: {'foo': '1.0.0'}).create();

    await pubGet();
    await d.cacheDir({'foo': '1.0.0', 'bar': '1.1.0'}).validate();
    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '1.0.0'),
      d.packageConfigEntry(name: 'bar', version: '1.1.0'),
    ]).validate();

    server.retractPackageVersion('bar', '1.1.0');
    await pubUpgrade();
    await d.cacheDir({'foo': '1.0.0', 'bar': '1.1.0'}).validate();
    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '1.0.0'),
      d.packageConfigEntry(name: 'bar', version: '1.1.0'),
    ]).validate();

    server.serve('bar', '2.0.0');
    await pubUpgrade();
    await d.cacheDir({'foo': '1.0.0', 'bar': '1.1.0'}).validate();
    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '1.0.0'),
      d.packageConfigEntry(name: 'bar', version: '1.1.0'),
    ]).validate();

    server.serve('bar', '1.2.0');
    await pubUpgrade();
    await d.cacheDir({'foo': '1.0.0', 'bar': '1.2.0'}).validate();
    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '1.0.0'),
      d.packageConfigEntry(name: 'bar', version: '1.2.0'),
    ]).validate();
  });

  test('Offline versions of pub commands also handle retracted packages',
      () async {
    final server = await servePackages();
    await populateCache(
      {
        'foo': ['1.0.0'],
        'bar': ['1.0.0', '1.1.0']
      },
      server,
    );

    await d.cacheDir({
      'foo': '1.0.0',
      'bar': ['1.0.0', '1.1.0']
    }).validate();

    final barVersionsCache =
        p.join(globalServer.cachingPath, '.cache', 'bar-versions.json');
    expect(fileExists(barVersionsCache), isTrue);
    deleteEntry(barVersionsCache);

    server.retractPackageVersion('bar', '1.1.0');
    await pubGet();

    await d.cacheDir({'bar': '1.1.0'}).validate();

    // Now serve only errors - to validate we are truly offline.
    server.serveErrors();

    await d.appDir(dependencies: {'foo': '1.0.0', 'bar': '^1.0.0'}).create();

    await pubUpgrade(args: ['--offline']);

    // We choose bar 1.1.0 since we already have it in pubspec.lock
    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '1.0.0'),
      d.packageConfigEntry(name: 'bar', version: '1.1.0'),
    ]).validate();

    // Delete lockfile so that retracted versions are not considered.
    final lockFile = p.join(d.sandbox, appPath, 'pubspec.lock');
    expect(fileExists(lockFile), isTrue);
    deleteEntry(lockFile);

    await pubGet(args: ['--offline']);
    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '1.0.0'),
      d.packageConfigEntry(name: 'bar', version: '1.0.0'),
    ]).validate();
  });

  test('Allow retracted version when pinned in dependency_overrides', () async {
    final server = await servePackages()
      ..serve('foo', '1.0.0')
      ..serve('foo', '2.0.0')
      ..serve('foo', '3.0.0');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependencies': {'foo': '<3.0.0'},
        'dependency_overrides': {'foo': '2.0.0'}
      })
    ]).create();

    server.retractPackageVersion('foo', '2.0.0');

    await pubGet();
    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '2.0.0'),
    ]).validate();
  });

  test('Prefer retracted version in dependency_overrides over pubspec.lock',
      () async {
    final server = await servePackages()
      ..serve('foo', '1.0.0')
      ..serve('foo', '2.0.0')
      ..serve('foo', '3.0.0');

    await d.appDir(dependencies: {'foo': 'any'}).create();
    await pubGet();

    server.retractPackageVersion('foo', '2.0.0');
    server.retractPackageVersion('foo', '3.0.0');

    await pubUpgrade();
    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '3.0.0'),
    ]).validate();

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependencies': {'foo': '<=3.0.0'},
        'dependency_overrides': {'foo': '2.0.0'}
      })
    ]).create();

    await pubUpgrade();
    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '2.0.0'),
    ]).validate();
  });
}
