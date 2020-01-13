// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE d.file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('shared dependency with same path', () async {
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
        'shared': {'path': '../shared'}
      })
    ]).create();

    await d.dir(appPath, [
      d.appPubspec({
        'foo': {'path': '../foo'},
        'bar': {'path': '../bar'}
      })
    ]).create();

    await pubGet();

    await d.appPackagesFile(
        {'foo': '../foo', 'bar': '../bar', 'shared': '../shared'}).validate();
  });

  test('shared dependency with paths that normalize the same', () async {
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
        'shared': {'path': '../././shared'}
      })
    ]).create();

    await d.dir(appPath, [
      d.appPubspec({
        'foo': {'path': '../foo'},
        'bar': {'path': '../bar'}
      })
    ]).create();

    await pubGet();

    await d.appPackagesFile(
        {'foo': '../foo', 'bar': '../bar', 'shared': '../shared'}).validate();
  });
}
