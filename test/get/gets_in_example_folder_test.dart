// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:test/test.dart';

import 'package:path/path.dart' as p;

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  forBothPubGetAndUpgrade((command) {
    test('pub ${command.name} also retrieves dependencies in example/',
        () async {
      await d.dir(appPath, [
        d.appPubspec(),
        d.dir('example', [
          d.pubspec({
            'name': 'app_example',
            'dependencies': {
              'myapp': {'path': '..'}
            }
          })
        ])
      ]).create();

      await pubCommand(command, args: ['--no-example']);
      final lockFile = File(p.join(d.sandbox, appPath, 'pubspec.lock'));
      final exampleLockFile = File(
        p.join(d.sandbox, appPath, 'example', 'pubspec.lock'),
      );

      expect(lockFile.existsSync(), true);
      expect(exampleLockFile.existsSync(), false);

      await pubCommand(command,
          output: command.name == 'get'
              ? '''
Resolving dependencies... 
Got dependencies!
Resolving dependencies in .${p.separator}example...
+ myapp 0.0.0 from path .
Changed 1 dependency!'''
              : '''
Resolving dependencies... 
No dependencies changed.
Resolving dependencies in .${p.separator}example...
+ myapp 0.0.0 from path .
Changed 1 dependency!''');
      expect(lockFile.existsSync(), true);
      expect(exampleLockFile.existsSync(), true);
    });

    test('paths are relative to cwd.', () async {
      await d.dir(appPath, [
        d.appPubspec(),
        d.dir('example', [
          d.pubspec({
            'name': 'broken name',
            'dependencies': {
              'myapp': {'path': '..'}
            }
          })
        ])
      ]).create();
      await pubGet(
          error: contains(
              'Error on line 1, column 9 of example${p.separator}pubspec.yaml'),
          exitCode: 65);
    });
  });
}
