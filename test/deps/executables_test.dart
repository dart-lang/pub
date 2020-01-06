// Copyright (c) 2016, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

const _validMain = 'main() {}';

void main() {
  Future<void> Function() _testExecutablesOutput(output, {bool dev = true}) =>
      () async {
        await pubGet();
        await runPub(
            args: ['deps', '--executables', if (dev) '--dev' else '--no-dev'],
            output: output);
      };

  Future<void> Function() _testAllDepsOutput(output) =>
      _testExecutablesOutput(output);
  Future<void> Function() _testNonDevDepsOutput(output) =>
      _testExecutablesOutput(output, dev: false);

  group('lists nothing when no executables found', () {
    setUp(() async {
      await d.dir(appPath, [d.appPubspec()]).create();
    });

    test('all dependencies', _testAllDepsOutput('\n'));
    test('non-dev dependencies', _testNonDevDepsOutput('\n'));
  });

  group('skips non-Dart executables', () {
    setUp(() async {
      await d.dir(appPath, [
        d.appPubspec(),
        d.dir('bin', [d.file('foo.py'), d.file('bar.sh')])
      ]).create();
    });

    test('all dependencies', _testAllDepsOutput('\n'));
    test('non-dev dependencies', _testNonDevDepsOutput('\n'));
  });

  group('skips Dart executables which are not parsable', () {
    setUp(() async {
      await d.dir(appPath, [
        d.appPubspec(),
        d.dir('bin', [d.file('foo.dart', 'main() {')])
      ]).create();
    });

    test('all dependencies', _testAllDepsOutput('\n'));
    test('non-dev dependencies', _testNonDevDepsOutput('\n'));
  });

  group('skips Dart executables without entrypoints', () {
    setUp(() async {
      await d.dir(appPath, [
        d.appPubspec(),
        d.dir(
            'bin', [d.file('foo.dart'), d.file('bar.dart', 'main(x, y, z) {}')])
      ]).create();
    });

    test('all dependencies', _testAllDepsOutput('\n'));
    test('non-dev dependencies', _testNonDevDepsOutput('\n'));
  });

  group('lists valid Dart executables with entrypoints', () {
    setUp(() async {
      await d.dir(appPath, [
        d.appPubspec(),
        d.dir('bin',
            [d.file('foo.dart', _validMain), d.file('bar.dart', _validMain)])
      ]).create();
    });

    test('all dependencies', _testAllDepsOutput('myapp: bar, foo'));
    test('non-dev dependencies', _testNonDevDepsOutput('myapp: bar, foo'));
  });

  group('skips executables in sub directories', () {
    setUp(() async {
      await d.dir(appPath, [
        d.appPubspec(),
        d.dir('bin', [
          d.file('foo.dart', _validMain),
          d.dir('sub', [d.file('bar.dart', _validMain)])
        ])
      ]).create();
    });

    test('all dependencies', _testAllDepsOutput('myapp:foo'));
    test('non-dev dependencies', _testNonDevDepsOutput('myapp:foo'));
  });

  group('lists executables from a dependency', () {
    setUp(() async {
      await d.dir('foo', [
        d.libPubspec('foo', '1.0.0'),
        d.dir('bin', [d.file('bar.dart', _validMain)])
      ]).create();

      await d.dir(appPath, [
        d.appPubspec({
          'foo': {'path': '../foo'}
        })
      ]).create();
    });

    test('all dependencies', _testAllDepsOutput('foo:bar'));
    test('non-dev dependencies', _testNonDevDepsOutput('foo:bar'));
  });

  group('lists executables only from immediate dependencies', () {
    setUp(() async {
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
    });

    test('all dependencies', _testAllDepsOutput('foo:bar'));
    test('non-dev dependencies', _testNonDevDepsOutput('foo:bar'));
  });

  group('applies formatting before printing executables', () {
    setUp(() async {
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
    });

    test('all dependencies', _testAllDepsOutput('''
        myapp
        foo: foo, baz
        bar:qux'''));
    test('non-dev dependencies', _testNonDevDepsOutput('''
        myapp
        foo: foo, baz
        bar:qux'''));
  });

  group('dev dependencies', () {
    setUp(() async {
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
    });

    test('are listed if --dev flag is set', _testAllDepsOutput('foo:bar'));
    test('are skipped if --no-dev flag is set', _testNonDevDepsOutput('\n'));
  });

  group('overriden dependencies executables', () {
    setUp(() async {
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
    });

    test(
        'are listed if --dev flag is set', _testAllDepsOutput('foo: bar, baz'));
    test('are listed if --no-dev flag is set',
        _testNonDevDepsOutput('foo: bar, baz'));
  });
}
