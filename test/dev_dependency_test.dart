// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'descriptor.dart' as d;
import 'test_pub.dart';

void main() {
  test("includes root package's dev dependencies", () async {
    await d
        .dir('foo', [d.libDir('foo'), d.libPubspec('foo', '0.0.1')]).create();

    await d
        .dir('bar', [d.libDir('bar'), d.libPubspec('bar', '0.0.1')]).create();

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dev_dependencies': {
          'foo': {'path': '../foo'},
          'bar': {'path': '../bar'},
        }
      })
    ]).create();

    await pubGet();

    await d.appPackagesFile({'foo': '../foo', 'bar': '../bar'}).validate();
  });

  test("includes dev dependency's transitive dependencies", () async {
    await d.dir('foo', [
      d.libDir('foo'),
      d.libPubspec('foo', '0.0.1', deps: {
        'bar': {'path': '../bar'}
      })
    ]).create();

    await d
        .dir('bar', [d.libDir('bar'), d.libPubspec('bar', '0.0.1')]).create();

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dev_dependencies': {
          'foo': {'path': '../foo'}
        }
      })
    ]).create();

    await pubGet();

    await d.appPackagesFile({'foo': '../foo', 'bar': '../bar'}).validate();
  });

  test("ignores transitive dependency's dev dependencies", () async {
    await d.dir('foo', [
      d.libDir('foo'),
      d.pubspec({
        'name': 'foo',
        'version': '0.0.1',
        'dev_dependencies': {
          'bar': {'path': '../bar'}
        }
      })
    ]).create();

    await d
        .dir('bar', [d.libDir('bar'), d.libPubspec('bar', '0.0.1')]).create();

    await d.dir(appPath, [
      d.appPubspec({
        'foo': {'path': '../foo'}
      })
    ]).create();

    await pubGet();

    await d.appPackagesFile({'foo': '../foo'}).validate();
  });
}
