// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Pub uses NTFS junction points to create links in the packages directory.
// These (unlike the symlinks that are supported in Vista and later) do not
// support relative paths. So this test, by design, will not pass on Windows.
// So just skip it.
@TestOn('!windows')
library;

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('generates a symlink with a relative path if the dependency '
      'path was relative', () async {
    await d.dir('foo', [
      d.libDir('foo'),
      d.libPubspec('foo', '0.0.1'),
    ]).create();

    await d.dir(appPath, [
      d.appPubspec(
        dependencies: {
          'foo': {'path': '../foo'},
        },
      ),
    ]).create();

    await pubGet();

    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', path: '../foo'),
    ]).validate();

    await d.dir('moved').create();

    // Move the app and package. Since they are still next to each other, it
    // should still be found and have the same relative path in the package
    // spec.
    renameInSandbox('foo', p.join('moved', 'foo'));
    renameInSandbox(appPath, p.join('moved', appPath));

    await d.dir('moved', [
      d.appPackageConfigFile([
        d.packageConfigEntry(name: 'foo', path: '../foo'),
      ]),
    ]).validate();
  });
}
