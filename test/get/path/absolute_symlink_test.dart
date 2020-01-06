// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE d.file.

import 'package:test/test.dart';

import 'package:path/path.dart' as path;

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
      d.appPubspec({
        'foo': {'path': fooPath}
      })
    ]).create();

    await pubGet();

    await d.dir(appPath, [
      d.packagesFile({'myapp': '.', 'foo': fooPath})
    ]).validate();

    await d.dir('moved').create();

    // Move the app but not the package. Since the symlink is absolute, it
    // should still be able to find it.
    renameInSandbox(appPath, path.join('moved', appPath));

    await d.dir('moved', [
      d.dir(appPath, [
        d.packagesFile({'myapp': '.', 'foo': fooPath})
      ])
    ]).validate();
  });
}
