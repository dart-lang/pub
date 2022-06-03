// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/validator.dart';
import 'package:pub/src/validator/dependency_override.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

Validator dependencyOverride() => DependencyOverrideValidator();

void main() {
  test(
      'should consider a package valid if it has dev dependency '
      'overrides', () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dev_dependencies': {'foo': '1.0.0'},
        'dependency_overrides': {'foo': '<3.0.0'}
      })
    ]).create();

    await expectValidation(dependencyOverride);
  });

  group('should consider a package invalid if', () {
    test('it has only non-dev dependency overrides', () async {
      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependency_overrides': {'foo': '<3.0.0'}
        })
      ]).create();

      await expectValidation(dependencyOverride, errors: isNotEmpty);
    });

    test('it has any non-dev dependency overrides', () async {
      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dev_dependencies': {'foo': '1.0.0'},
          'dependency_overrides': {
            'foo': '<3.0.0',
            'bar': '>3.0.0',
          }
        })
      ]).create();

      await expectValidation(dependencyOverride, errors: isNotEmpty);
    });
  });
}
