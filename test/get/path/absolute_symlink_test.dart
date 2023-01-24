// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test(
      'generates a symlink with an absolute path if the dependency '
      'path was absolute', () async {
    await d
        .dir('foo', [d.libDir('foo'), d.libPubspec('foo', '0.0.1')]).create();

    var fooPath = d.path('foo');
    await d.dir(appPath, [
      d.appPubspec(
        dependencies: {
          'foo': {'path': fooPath}
        },
      )
    ]).create();

    await pubGet();

    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', path: fooPath),
    ]).validate();

    await d.dir('moved').create();

    // Move the app but not the package. Since the symlink is absolute, it
    // should still be able to find it.
    renameInSandbox(appPath, path.join('moved', appPath));

    await d.dir('moved', [
      d.appPackageConfigFile([
        d.packageConfigEntry(name: 'foo', path: fooPath),
      ]),
    ]).validate();
  });
}
