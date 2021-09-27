// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart = 2.11

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

final dotExample = p.join('.', 'example');

void main() {
  forBothPubGetAndUpgrade((command) {
    test(
        'pub ${command.name} --example also retrieves dependencies in example/',
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

      await pubCommand(command, args: []);
      final lockFile = File(p.join(d.sandbox, appPath, 'pubspec.lock'));
      final exampleLockFile = File(
        p.join(d.sandbox, appPath, 'example', 'pubspec.lock'),
      );

      expect(lockFile.existsSync(), true);
      expect(exampleLockFile.existsSync(), false);
      await pubCommand(command,
          args: ['--example'],
          output: command.name == 'get'
              ? '''
Resolving dependencies... 
Got dependencies!
Resolving dependencies in $dotExample...
Got dependencies in $dotExample.'''
              : '''
Resolving dependencies... 
No dependencies changed.
Resolving dependencies in $dotExample...
Got dependencies in $dotExample.''');
      expect(lockFile.existsSync(), true);
      expect(exampleLockFile.existsSync(), true);
    });

    test('Failures are met with a suggested command', () async {
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
        args: ['--example'],
        error: contains(
            'Resolving dependencies in $dotExample failed. For details run `dart pub get --directory $dotExample`'),
        exitCode: 1,
      );
      await pubGet(
        args: ['--directory', dotExample],
        error: contains(
            'Error on line 1, column 9 of example${p.separator}pubspec.yaml'),
        exitCode: exit_codes.DATA,
      );
    });
  });
}
