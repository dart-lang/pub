// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/validator/pubspec.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

void main() {
  test('should consider a package valid if it has a pubspec', () async {
    await d.validPackage().create();

    await expectValidationDeprecated(PubspecValidator.new);
  });

  test(
    'should consider a package invalid if it has a .gitignored pubspec',
    () async {
      final repo = d.git(appPath, [d.file('.gitignore', 'pubspec.yaml')]);
      await d.validPackage().create();
      await repo.create();

      await expectValidationDeprecated(
        PubspecValidator.new,
        errors: isNotEmpty,
      );
    },
  );
}
