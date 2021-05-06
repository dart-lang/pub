// Copyright (c) 2016, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart=2.10

import 'package:pub/src/ascii_tree.dart' as tree;
import 'package:pub/src/io.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../golden_file.dart';
import '../test_pub.dart';

const _validMain = 'main() {}';
const _invalidMain = 'main() {';

Future<void> variations(String name) async {
  final buffer = StringBuffer();
  buffer.writeln(
      tree.fromFiles(listDir(d.sandbox, recursive: true), baseDir: d.sandbox));

  await pubGet();
  await runPubIntoBuffer(['deps', '--executables'], buffer);
  await runPubIntoBuffer(['deps', '--executables', '--dev'], buffer);
  // The json ouput also lists the exectuables.
  await runPubIntoBuffer(['deps', '--json'], buffer);
  // The easiest way to update the golden files is to delete them and rerun the
  // test.
  expectMatchesGoldenFile(buffer.toString(), 'test/deps/goldens/$name.txt');
}

void main() {
  test('skips non-Dart executables', () async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir('bin', [d.file('foo.py'), d.file('bar.sh')])
    ]).create();
    await variations('non_dart_executables');
  });

  test('lists Dart executables, even without entrypoints', () async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir(
        'bin',
        [d.file('foo.dart', _validMain), d.file('bar.dart', _invalidMain)],
      )
    ]).create();
    await variations('dart_executables');
  });

  test('skips executables in sub directories', () async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir('bin', [
        d.file('foo.dart', _validMain),
        d.dir('sub', [d.file('bar.dart', _validMain)])
      ])
    ]).create();
    await variations('nothing_in_sub_drectories');
  });

  test('lists executables from a dependency', () async {
    await d.dir('foo', [
      d.libPubspec('foo', '1.0.0'),
      d.dir('bin', [d.file('bar.dart', _validMain)])
    ]).create();

    await d.dir(appPath, [
      d.appPubspec({
        'foo': {'path': '../foo'}
      })
    ]).create();

    await variations('from_dependency');
  });

  test('lists executables only from immediate dependencies', () async {
    await d.dir(appPath, [
      d.appPubspec({
        'foo': {'path': '../foo'}
      })
    ]).create();

    await d.dir('foo', [
      d.libPubspec('foo', '1.0.0', deps: {
        'baz': {'path': '../baz'}
      }),
      d.dir('bin', [d.file('bar.dart', _validMain)])
    ]).create();

    await d.dir('baz', [
      d.libPubspec('baz', '1.0.0'),
      d.dir('bin', [d.file('qux.dart', _validMain)])
    ]).create();

    await variations('only_immediate');
  });

  test('applies formatting before printing executables', () async {
    await d.dir(appPath, [
      d.appPubspec({
        'foo': {'path': '../foo'},
        'bar': {'path': '../bar'}
      }),
      d.dir('bin', [d.file('myapp.dart', _validMain)])
    ]).create();

    await d.dir('foo', [
      d.libPubspec('foo', '1.0.0'),
      d.dir('bin',
          [d.file('baz.dart', _validMain), d.file('foo.dart', _validMain)])
    ]).create();

    await d.dir('bar', [
      d.libPubspec('bar', '1.0.0'),
      d.dir('bin', [d.file('qux.dart', _validMain)])
    ]).create();

    await variations('formatting');
  });

  test('dev dependencies', () async {
    await d.dir('foo', [
      d.libPubspec('foo', '1.0.0'),
      d.dir('bin', [d.file('bar.dart', _validMain)])
    ]).create();

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dev_dependencies': {
          'foo': {'path': '../foo'}
        }
      })
    ]).create();
    await variations('dev_dependencies');
  });

  test('overriden dependencies executables', () async {
    await d.dir('foo-1.0', [
      d.libPubspec('foo', '1.0.0'),
      d.dir('bin', [d.file('bar.dart', _validMain)])
    ]).create();

    await d.dir('foo-2.0', [
      d.libPubspec('foo', '2.0.0'),
      d.dir('bin',
          [d.file('bar.dart', _validMain), d.file('baz.dart', _validMain)])
    ]).create();

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependencies': {
          'foo': {'path': '../foo-1.0'}
        },
        'dependency_overrides': {
          'foo': {'path': '../foo-2.0'}
        }
      })
    ]).create();
    await variations('overrides');
  });
}
