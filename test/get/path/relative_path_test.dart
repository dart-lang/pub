// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart=2.10

import 'package:path/path.dart' as path;
import 'package:pub/src/lock_file.dart';
import 'package:pub/src/source_registry.dart';
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('can use relative path', () async {
    await d
        .dir('foo', [d.libDir('foo'), d.libPubspec('foo', '0.0.1')]).create();

    await d.dir(appPath, [
      d.appPubspec({
        'foo': {'path': '../foo'}
      })
    ]).create();

    await pubGet();

    await d.appPackagesFile({'foo': '../foo'}).validate();
  });

  test('path is relative to containing pubspec', () async {
    await d.dir('relative', [
      d.dir('foo', [
        d.libDir('foo'),
        d.libPubspec('foo', '0.0.1', deps: {
          'bar': {'path': '../bar'}
        })
      ]),
      d.dir('bar', [d.libDir('bar'), d.libPubspec('bar', '0.0.1')])
    ]).create();

    await d.dir(appPath, [
      d.appPubspec({
        'foo': {'path': '../relative/foo'}
      })
    ]).create();

    await pubGet();

    await d.appPackagesFile(
        {'foo': '../relative/foo', 'bar': '../relative/bar'}).validate();
  });

  test('path is relative to containing pubspec when using --directory',
      () async {
    await d.dir('relative', [
      d.dir('foo', [
        d.libDir('foo'),
        d.libPubspec('foo', '0.0.1', deps: {
          'bar': {'path': '../bar'}
        })
      ]),
      d.dir('bar', [d.libDir('bar'), d.libPubspec('bar', '0.0.1')])
    ]).create();

    await d.dir(appPath, [
      d.appPubspec({
        'foo': {'path': '../relative/foo'}
      })
    ]).create();

    await pubGet(
        args: ['--directory', appPath],
        workingDirectory: d.sandbox,
        output: contains('Changed 2 dependencies in myapp!'));

    await d.appPackagesFile(
      {'foo': '../relative/foo', 'bar': '../relative/bar'},
    ).validate();
  });

  test('relative path preserved in the lockfile', () async {
    await d
        .dir('foo', [d.libDir('foo'), d.libPubspec('foo', '0.0.1')]).create();

    await d.dir(appPath, [
      d.appPubspec({
        'foo': {'path': '../foo'}
      })
    ]).create();

    await pubGet();

    var lockfilePath = path.join(d.sandbox, appPath, 'pubspec.lock');
    var lockfile = LockFile.load(lockfilePath, SourceRegistry());
    var description = lockfile.packages['foo'].description;

    expect(description['relative'], isTrue);
    expect(description['path'], path.join(d.sandbox, 'foo'));
  });
}
