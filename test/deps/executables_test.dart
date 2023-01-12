// Copyright (c) 2016, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../descriptor.dart' as d;
import '../golden_file.dart';
import '../test_pub.dart';

const _validMain = 'main() {}';
const _invalidMain = 'main() {';

extension on GoldenTestContext {
  Future<void> runExecutablesTest() async {
    await pubGet();

    await tree();

    await run(['deps', '--executables']);
    await run(['deps', '--executables', '--dev']);
    await run(['deps', '--json']);
  }
}

void main() {
  testWithGolden('skips non-Dart executables', (ctx) async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir('bin', [d.file('foo.py'), d.file('bar.sh')])
    ]).create();

    await ctx.runExecutablesTest();
  });

  testWithGolden('lists Dart executables, without entrypoints', (ctx) async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir(
        'bin',
        [d.file('foo.dart', _validMain), d.file('bar.dart', _invalidMain)],
      )
    ]).create();

    await ctx.runExecutablesTest();
  });

  testWithGolden('skips executables in sub directories', (ctx) async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir('bin', [
        d.file('foo.dart', _validMain),
        d.dir('sub', [d.file('bar.dart', _validMain)])
      ])
    ]).create();

    await ctx.runExecutablesTest();
  });

  testWithGolden('lists executables from a dependency', (ctx) async {
    await d.dir('foo', [
      d.libPubspec('foo', '1.0.0'),
      d.dir('bin', [d.file('bar.dart', _validMain)])
    ]).create();

    await d.dir(appPath, [
      d.appPubspec(
        dependencies: {
          'foo': {'path': '../foo'}
        },
      )
    ]).create();

    await ctx.runExecutablesTest();
  });

  testWithGolden('lists executables only from immediate dependencies',
      (ctx) async {
    await d.dir(appPath, [
      d.appPubspec(
        dependencies: {
          'foo': {'path': '../foo'}
        },
      )
    ]).create();

    await d.dir('foo', [
      d.libPubspec(
        'foo',
        '1.0.0',
        deps: {
          'baz': {'path': '../baz'}
        },
      ),
      d.dir('bin', [d.file('bar.dart', _validMain)])
    ]).create();

    await d.dir('baz', [
      d.libPubspec('baz', '1.0.0'),
      d.dir('bin', [d.file('qux.dart', _validMain)])
    ]).create();

    await ctx.runExecutablesTest();
  });

  testWithGolden('applies formatting before printing executables', (ctx) async {
    await d.dir(appPath, [
      d.appPubspec(
        dependencies: {
          'foo': {'path': '../foo'},
          'bar': {'path': '../bar'}
        },
      ),
      d.dir('bin', [d.file('myapp.dart', _validMain)])
    ]).create();

    await d.dir('foo', [
      d.libPubspec('foo', '1.0.0'),
      d.dir(
        'bin',
        [d.file('baz.dart', _validMain), d.file('foo.dart', _validMain)],
      )
    ]).create();

    await d.dir('bar', [
      d.libPubspec('bar', '1.0.0'),
      d.dir('bin', [d.file('qux.dart', _validMain)])
    ]).create();

    await ctx.runExecutablesTest();
  });

  testWithGolden('dev dependencies', (ctx) async {
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

    await ctx.runExecutablesTest();
  });

  testWithGolden('overriden dependencies executables', (ctx) async {
    await d.dir('foo-1.0', [
      d.libPubspec('foo', '1.0.0'),
      d.dir('bin', [d.file('bar.dart', _validMain)])
    ]).create();

    await d.dir('foo-2.0', [
      d.libPubspec('foo', '2.0.0'),
      d.dir(
        'bin',
        [d.file('bar.dart', _validMain), d.file('baz.dart', _validMain)],
      )
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

    await ctx.runExecutablesTest();
  });
}
