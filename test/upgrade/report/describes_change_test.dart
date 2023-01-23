// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart';
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('Shows count of discontinued packages', () async {
    final server = await servePackages();

    server.serve('foo', '2.0.0');

    server.discontinue('foo');

    // Create the first lockfile.
    await d.appDir(dependencies: {'foo': '2.0.0'}).create();

    await pubGet();

    // Do the dry run.
    await pubUpgrade(
      args: ['--dry-run'],
      output: contains('1 package is discontinued.'),
    );

    // Try without --dry-run
    await pubUpgrade(
      output: contains('1 package is discontinued.'),
    );
  });

  test('shows how package changed from previous lockfile', () async {
    final server = await servePackages();

    server.serve('unchanged', '1.0.0');
    server.serve('version_upgraded', '1.0.0');
    server.serve('version_upgraded', '2.0.0');
    server.serve('version_downgraded', '1.0.0');
    server.serve('version_downgraded', '2.0.0');
    server.serve('contents_changed', '1.0.0');
    server.serve('source_changed', '1.0.0');
    server.serve('package_added', '1.0.0');
    server.serve('package_removed', '1.0.0');

    await d.dir('source_changed', [
      d.libDir('source_changed'),
      d.libPubspec('source_changed', '2.0.0')
    ]).create();

    await d.dir('description_changed_1', [
      d.libDir('description_changed'),
      d.libPubspec('description_changed', '1.0.0')
    ]).create();

    await d.dir('description_changed_2', [
      d.libDir('description_changed'),
      d.libPubspec('description_changed', '1.0.0')
    ]).create();

    // Create the first lockfile.
    await d.appDir(
      dependencies: {
        'unchanged': 'any',
        'contents_changed': '1.0.0',
        'version_upgraded': '1.0.0',
        'version_downgraded': '2.0.0',
        'source_changed': 'any',
        'package_removed': 'any',
        'description_changed': {'path': '../description_changed_1'}
      },
    ).create();

    await pubGet();
    server.serve(
      'contents_changed',
      '1.0.0',
      contents: [d.file('Sneaky.txt', 'Very sneaky attack on integrity.')],
    );

    // Change the pubspec.
    await d.appDir(
      dependencies: {
        'unchanged': 'any',
        'version_upgraded': 'any',
        'version_downgraded': '1.0.0',
        'source_changed': {'path': '../source_changed'},
        'package_added': 'any',
        'description_changed': {'path': '../description_changed_2'},
        'contents_changed': '1.0.0',
      },
    ).create();

    // Upgrade everything.
    await pubUpgrade(
      output: allOf([
        contains('Resolving dependencies...'),
        contains(
          '* description_changed 1.0.0 from path ..${separator}description_changed_2 (was 1.0.0 from path ..${separator}description_changed_1)',
        ),
        contains('  unchanged 1.0.0'),
        contains(
          '* source_changed 2.0.0 from path ..${separator}source_changed (was 1.0.0)',
        ),
        contains('> version_upgraded 2.0.0 (was 1.0.0'),
        contains('< version_downgraded 1.0.0 (was 2.0.0'),
        contains('+ package_added 1.0.0'),
        contains('- package_removed 1.0.0'),
        contains('~ contents_changed 1.0.0 (was 1.0.0)'),
      ]),
      environment: {'PUB_ALLOW_PRERELEASE_SDK': 'false'},
    );
  });
}
