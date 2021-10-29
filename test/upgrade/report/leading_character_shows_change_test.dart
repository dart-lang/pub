// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('the character before each package describes the change', () async {
    await servePackages((builder) {
      builder.serve('added', '1.0.0');
      builder.serve('downgraded', '1.0.0');
      builder.serve('downgraded', '2.0.0');
      builder.serve('overridden', '1.0.0');
      builder.serve('removed', '1.0.0');
      builder.serve('source_changed', '1.0.0');
      builder.serve('upgraded', '1.0.0');
      builder.serve('upgraded', '2.0.0');
      builder.serve('unchanged', '1.0.0');
    });

    await d.dir('description_changed_1', [
      d.libDir('description_changed'),
      d.libPubspec('description_changed', '1.0.0')
    ]).create();

    await d.dir('description_changed_2', [
      d.libDir('description_changed'),
      d.libPubspec('description_changed', '1.0.0')
    ]).create();

    await d.dir('source_changed', [
      d.libDir('source_changed'),
      d.libPubspec('source_changed', '1.0.0')
    ]).create();

    // Create the first lockfile.
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependencies': {
          'description_changed': {'path': '../description_changed_1'},
          'downgraded': '2.0.0',
          'removed': 'any',
          'source_changed': 'any',
          'unchanged': 'any',
          'upgraded': '1.0.0'
        },
        'dependency_overrides': {'overridden': 'any'}
      })
    ]).create();

    await pubGet();

    // Change the pubspec.
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependencies': {
          'added': 'any',
          'description_changed': {'path': '../description_changed_2'},
          'downgraded': '1.0.0',
          'source_changed': {'path': '../source_changed'},
          'unchanged': 'any',
          'upgraded': '2.0.0'
        },
        'dependency_overrides': {'overridden': 'any'}
      })
    ]).create();

    // Upgrade everything.
    await pubUpgrade(output: RegExp(r'''
Resolving dependencies\.\.\..*
\+ added .*
\* description_changed .*
< downgraded .*
! overridden .*
\* source_changed .*
  unchanged .*
> upgraded .*
These packages are no longer being depended on:
- removed .*
''', multiLine: true), environment: {'PUB_ALLOW_PRERELEASE_SDK': 'false'});
  });
}
