// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'descriptor.dart' as d;
import 'test_pub.dart';

void main() {
  forBothPubGetAndUpgrade((command) {
    test('supports dependency_overrides', () async {
      await servePackages()
        ..serve('lib', '1.0.0')
        ..serve('lib', '2.0.0');

      await d.dir(appPath, [
        d.appPubspec({'lib': '1.0.0'}),
        d.dir('lib'),
        d.pubspecOverrides({
          'dependency_overrides': {'lib': '2.0.0'}
        }),
      ]).create();

      await pubCommand(
        command,
        warning:
            'Warning: pubspec.yaml has overrides from pubspec_overrides.yaml\n'
            'Warning: You are using these overridden dependencies:\n'
            '! lib 2.0.0',
      );

      await d.dir(appPath, [
        d.packageConfigFile([
          d.packageConfigEntry(
            name: 'lib',
            version: '2.0.0',
            languageVersion: '3.0',
          ),
          d.packageConfigEntry(
            name: 'myapp',
            path: '.',
            languageVersion: '3.0',
          ),
        ])
      ]).validate();
    });
  });
}
