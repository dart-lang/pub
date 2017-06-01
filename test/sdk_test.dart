// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE d.file.

import 'package:path/path.dart' as p;

import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

import 'descriptor.dart' as d;
import 'test_pub.dart';

main() {
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
        ])
      ]).create();
    });

    test("gets an SDK dependency's dependencies", () async {
      await d.appDir({
        "foo": {"sdk": "flutter"}
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

    test("unlocks an SDK dependency when the version changes", () async {
      await d.appDir({
        "foo": {"sdk": "flutter"}
      }).create();
      await pubCommand(command,
          environment: {'FLUTTER_ROOT': p.join(d.sandbox, 'flutter')});

      await d
          .file("$appPath/pubspec.lock",
              allOf([contains("0.0.1"), isNot(contains("0.0.2"))]))
          .validate();

      await d
          .dir('flutter/packages/foo', [d.libPubspec('foo', '0.0.2')]).create();
      await pubCommand(command,
          environment: {'FLUTTER_ROOT': p.join(d.sandbox, 'flutter')});

      await d
          .file("$appPath/pubspec.lock",
              allOf([isNot(contains("0.0.1")), contains("0.0.2")]))
          .validate();
    });

    group("fails if", () {
      test("the version constraint doesn't match", () async {
        await d.appDir({
          "foo": {"sdk": "flutter", "version": "^1.0.0"}
        }).create();
        await pubCommand(command,
            environment: {'FLUTTER_ROOT': p.join(d.sandbox, 'flutter')},
            error: 'Package foo has no versions that match >=1.0.0 <2.0.0 '
                'derived from:\n'
                '- myapp depends on version ^1.0.0');
      });

      test("the SDK is unknown", () async {
        await d.appDir({
          "foo": {"sdk": "unknown"}
        }).create();
        await pubCommand(command,
            error: 'Unknown SDK "unknown".\n'
                'Depended on by:\n'
                '- myapp',
            exitCode: exit_codes.UNAVAILABLE);
      });

      test("the SDK is unavailable", () async {
        await d.appDir({
          "foo": {"sdk": "flutter"}
        }).create();
        await pubCommand(command,
            error: 'The Flutter SDK is not available.\n'
                'Depended on by:\n'
                '- myapp',
            exitCode: exit_codes.UNAVAILABLE);
      });

      test("the SDK doesn't contain the package", () async {
        await d.appDir({
          "bar": {"sdk": "flutter"}
        }).create();
        await pubCommand(command,
            environment: {'FLUTTER_ROOT': p.join(d.sandbox, 'flutter')},
            error: 'Could not find package bar in the Flutter SDK.\n'
                'Depended on by:\n'
                '- myapp',
            exitCode: exit_codes.UNAVAILABLE);
      });

      test("the Dart SDK doesn't contain the package", () async {
        await d.appDir({
          "bar": {"sdk": "dart"}
        }).create();
        await pubCommand(command,
            error: 'Could not find package bar in the Dart SDK.\n'
                'Depended on by:\n'
                '- myapp',
            exitCode: exit_codes.UNAVAILABLE);
      });
    });
  });
}
