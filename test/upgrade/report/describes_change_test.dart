// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('shows how package changed from previous lockfile', () async {
    await servePackages((builder) {
      builder.serve('unchanged', '1.0.0');
      builder.serve('version_changed', '1.0.0');
      builder.serve('version_changed', '2.0.0');
      builder.serve('source_changed', '1.0.0');
    });

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
    await d.appDir({
      'unchanged': 'any',
      'version_changed': '1.0.0',
      'source_changed': 'any',
      'description_changed': {'path': '../description_changed_1'}
    }).create();

    await pubGet();

    // Change the pubspec.
    await d.appDir({
      'unchanged': 'any',
      'version_changed': 'any',
      'source_changed': {'path': '../source_changed'},
      'description_changed': {'path': '../description_changed_2'}
    }).create();

    // Upgrade everything.
    await pubUpgrade(output: RegExp(r'''
Resolving dependencies\.\.\..*
. description_changed 1\.0\.0 from path \.\.[/\\]description_changed_2 \(was 1\.0\.0 from path \.\.[/\\]description_changed_1\)
. source_changed 2\.0\.0 from path \.\.[/\\]source_changed \(was 1\.0\.0\)
. unchanged 1\.0\.0
. version_changed 2\.0\.0 \(was 1\.0\.0\)
''', multiLine: true), environment: {'PUB_ALLOW_PRERELEASE_SDK': 'false'});
  });
}
