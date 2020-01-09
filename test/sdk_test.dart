// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE d.file.

import 'package:path/path.dart' as p;

import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:pub/src/io.dart';

import 'descriptor.dart' as d;
import 'test_pub.dart';

void main() {
  forBothPubGetAndUpgrade((command) {
    setUp(() async {
      await servePackages((builder) {
        builder.serve('bar', '1.0.0');
      });

      await d.dir('flutter', [
        d.dir('packages', [
          d.dir('foo', [
            d.libDir('foo', 'foo 0.0.1'),
            d.libPubspec('foo', '0.0.1', deps: {'bar': 'any'})
          ])
        ]),
        d.dir('bin/cache/pkg', [
          d.dir('baz',
              [d.libDir('baz', 'foo 0.0.1'), d.libPubspec('baz', '0.0.1')])
        ]),
        d.file('version', '1.2.3')
      ]).create();
    });

    test("gets an SDK dependency's dependencies", () async {
      await d.appDir({
        'foo': {'sdk': 'flutter'}
      }).create();
      await pubCommand(command,
          environment: {'FLUTTER_ROOT': p.join(d.sandbox, 'flutter')});

      await d.dir(appPath, [
        d.packagesFile({
          'myapp': '.',
          'foo': p.join(d.sandbox, 'flutter', 'packages', 'foo'),
          'bar': '1.0.0'
        })
      ]).validate();
    });

    test('gets an SDK dependency from bin/cache/pkg', () async {
      await d.appDir({
        'baz': {'sdk': 'flutter'}
      }).create();
      await pubCommand(command,
          environment: {'FLUTTER_ROOT': p.join(d.sandbox, 'flutter')});

      await d.dir(appPath, [
        d.packagesFile({
          'myapp': '.',
          'baz': p.join(d.sandbox, 'flutter', 'bin', 'cache', 'pkg', 'baz')
        })
      ]).validate();
    });

    test('unlocks an SDK dependency when the version changes', () async {
      await d.appDir({
        'foo': {'sdk': 'flutter'}
      }).create();
      await pubCommand(command,
          environment: {'FLUTTER_ROOT': p.join(d.sandbox, 'flutter')});

      await d
          .file('$appPath/pubspec.lock',
              allOf([contains('0.0.1'), isNot(contains('0.0.2'))]))
          .validate();

      await d
          .dir('flutter/packages/foo', [d.libPubspec('foo', '0.0.2')]).create();
      await pubCommand(command,
          environment: {'FLUTTER_ROOT': p.join(d.sandbox, 'flutter')});

      await d
          .file('$appPath/pubspec.lock',
              allOf([isNot(contains('0.0.1')), contains('0.0.2')]))
          .validate();
    });

    // Regression test for #1883
    test(
        "doesn't fail if the Flutter SDK's version file doesn't exist when "
        'nothing depends on Flutter', () async {
      await d.appDir().create();
      deleteEntry(p.join(d.sandbox, 'flutter', 'version'));
      await pubCommand(command,
          environment: {'FLUTTER_ROOT': p.join(d.sandbox, 'flutter')});

      await d.dir(appPath, [
        d.packagesFile({'myapp': '.'})
      ]).validate();
    });

    group('fails if', () {
      test("the version constraint doesn't match", () async {
        await d.appDir({
          'foo': {'sdk': 'flutter', 'version': '^1.0.0'}
        }).create();
        await pubCommand(command,
            environment: {'FLUTTER_ROOT': p.join(d.sandbox, 'flutter')},
            error: equalsIgnoringWhitespace("""
              Because myapp depends on foo ^1.0.0 from sdk which doesn't match
                any versions, version solving failed.
            """));
      });

      test('the SDK is unknown', () async {
        await d.appDir({
          'foo': {'sdk': 'unknown'}
        }).create();
        await pubCommand(command, error: equalsIgnoringWhitespace("""
              Because myapp depends on foo any from sdk which doesn't exist
                (unknown SDK "unknown"), version solving failed.
            """), exitCode: exit_codes.UNAVAILABLE);
      });

      test('the SDK is unavailable', () async {
        await d.appDir({
          'foo': {'sdk': 'flutter'}
        }).create();
        await pubCommand(command, error: equalsIgnoringWhitespace("""
              Because myapp depends on foo any from sdk which doesn't exist (the
                Flutter SDK is not available), version solving failed.

              Flutter users should run `flutter pub get` instead of `pub
                get`.
            """), exitCode: exit_codes.UNAVAILABLE);
      });

      test("the SDK doesn't contain the package", () async {
        await d.appDir({
          'bar': {'sdk': 'flutter'}
        }).create();
        await pubCommand(command,
            environment: {'FLUTTER_ROOT': p.join(d.sandbox, 'flutter')},
            error: equalsIgnoringWhitespace("""
              Because myapp depends on bar any from sdk which doesn't exist
                (could not find package bar in the Flutter SDK), version solving
                failed.
            """),
            exitCode: exit_codes.UNAVAILABLE);
      });

      test("the Dart SDK doesn't contain the package", () async {
        await d.appDir({
          'bar': {'sdk': 'dart'}
        }).create();
        await pubCommand(command, error: equalsIgnoringWhitespace("""
              Because myapp depends on bar any from sdk which doesn't exist
                (could not find package bar in the Dart SDK), version solving
                failed.
            """), exitCode: exit_codes.UNAVAILABLE);
      });
    });

    test('supports the Fuchsia SDK', () async {
      renameDir(p.join(d.sandbox, 'flutter'), p.join(d.sandbox, 'fuchsia'));

      await d.appDir({
        'foo': {'sdk': 'fuchsia'}
      }).create();
      await pubCommand(command,
          environment: {'FUCHSIA_DART_SDK_ROOT': p.join(d.sandbox, 'fuchsia')});

      await d.dir(appPath, [
        d.packagesFile({
          'myapp': '.',
          'foo': p.join(d.sandbox, 'fuchsia', 'packages', 'foo'),
          'bar': '1.0.0'
        })
      ]).validate();
    });
  });
}
