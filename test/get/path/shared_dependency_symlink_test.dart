// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE d.file.

import 'package:test/test.dart';

import 'package:path/path.dart' as path;

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('shared dependency with symlink', () async {
    await d.dir('shared',
        [d.libDir('shared'), d.libPubspec('shared', '0.0.1')]).create();

    await d.dir('foo', [
      d.libDir('foo'),
      d.libPubspec('foo', '0.0.1', deps: {
        'shared': {'path': '../shared'}
      })
    ]).create();

    await d.dir('bar', [
      d.libDir('bar'),
      d.libPubspec('bar', '0.0.1', deps: {
        'shared': {'path': '../link/shared'}
      })
    ]).create();

    await d.dir(appPath, [
      d.appPubspec({
        'bar': {'path': '../bar'},
        'foo': {'path': '../foo'},
      })
    ]).create();

    await d.dir('link').create();
    symlinkInSandbox('shared', path.join('link', 'shared'));

    await pubGet();

    await d.dir(appPath, [
      d.packagesFile({
        'myapp': '.',
        'foo': '../foo',
        'bar': '../bar',
        'shared': '../shared'
      })
    ]).validate();
  });
}
