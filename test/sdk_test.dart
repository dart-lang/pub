// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE d.file.

import 'package:path/path.dart' as p;

import 'package:scheduled_test/scheduled_test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

import 'descriptor.dart' as d;
import 'test_pub.dart';

main() {
  forBothPubGetAndUpgrade((command) {
    setUp(() {
      servePackages((builder) {
        builder.serve('bar', '1.0.0');
      });

      d.dir('flutter', [
        d.dir('packages', [
          d.dir('foo', [
            d.libDir('foo', 'foo 0.0.1'),
            d.libPubspec('foo', '0.0.1', deps: {'bar': 'any'})
          ])
        ])
      ]).create();
    });

    integration("gets an SDK dependency's dependencies", () {
      d.appDir({
        "foo": {"sdk": "flutter"}
      }).create();
      pubCommand(command,
          environment: {'FLUTTER_ROOT': p.join(sandboxDir, 'flutter')});

      d.dir(appPath, [
        d.packagesFile({
          'myapp': '.',
          'foo': p.join(sandboxDir, 'flutter', 'packages', 'foo'),
          'bar': '1.0.0'
        })
      ]).validate();
    });

    integration("unlocks an SDK dependency when the version changes", () {
      d.appDir({
        "foo": {"sdk": "flutter"}
      }).create();
      pubCommand(command,
          environment: {'FLUTTER_ROOT': p.join(sandboxDir, 'flutter')});

      d
          .matcherFile("$appPath/pubspec.lock",
              allOf([contains("0.0.1"), isNot(contains("0.0.2"))]))
          .validate();

      d.dir('flutter/packages/foo', [d.libPubspec('foo', '0.0.2')]).create();
      pubCommand(command,
          environment: {'FLUTTER_ROOT': p.join(sandboxDir, 'flutter')});

      d
          .matcherFile("$appPath/pubspec.lock",
              allOf([isNot(contains("0.0.1")), contains("0.0.2")]))
          .validate();
    });

    group("fails if", () {
      integration("the version constraint doesn't match", () {
        d.appDir({
          "foo": {"sdk": "flutter", "version": "^1.0.0"}
        }).create();
        pubCommand(command,
            environment: {'FLUTTER_ROOT': p.join(sandboxDir, 'flutter')},
            error: 'Package foo has no versions that match >=1.0.0 <2.0.0 '
                'derived from:\n'
                '- myapp depends on version ^1.0.0');
      });

      integration("the SDK is unknown", () {
        d.appDir({
          "foo": {"sdk": "unknown"}
        }).create();
        pubCommand(command,
            error: 'Unknown SDK "unknown".\n'
                'Depended on by:\n'
                '- myapp',
            exitCode: exit_codes.UNAVAILABLE);
      });

      integration("the SDK is unavailable", () {
        d.appDir({
          "foo": {"sdk": "flutter"}
        }).create();
        pubCommand(command,
            error: 'The Flutter SDK is not available.\n'
                'Depended on by:\n'
                '- myapp',
            exitCode: exit_codes.UNAVAILABLE);
      });

      integration("the SDK doesn't contain the package", () {
        d.appDir({
          "bar": {"sdk": "flutter"}
        }).create();
        pubCommand(command,
            environment: {'FLUTTER_ROOT': p.join(sandboxDir, 'flutter')},
            error: 'Could not find package bar in the Flutter SDK.\n'
                'Depended on by:\n'
                '- myapp',
            exitCode: exit_codes.UNAVAILABLE);
      });

      integration("the Dart SDK doesn't contain the package", () {
        d.appDir({
          "bar": {"sdk": "dart"}
        }).create();
        pubCommand(command,
            error: 'Could not find package bar in the Dart SDK.\n'
                'Depended on by:\n'
                '- myapp',
            exitCode: exit_codes.UNAVAILABLE);
      });
    });
  });
}
