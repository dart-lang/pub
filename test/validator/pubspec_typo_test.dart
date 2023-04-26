// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/validator.dart';
import 'package:pub/src/validator/pubspec_typo.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

Validator pubspecTypo() => PubspecTypoValidator();

void main() {
  group('should consider a package valid if it', () {
    setUp(d.validPackage().create);

    test('looks normal', () => expectValidationDeprecated(pubspecTypo));

    test('has no typos', () async {
      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'version': '1.0.0',
          'description': 'My app.',
          'homepage': 'https://my.homepage.com',
          'repository': 'my-repo',
          'issue_tracker': '',
          'documentation': '',
          'dependencies': {},
          'dev_dependencies': {},
          'dependency_overrides': {},
          'environment': {},
          'executables': '',
          'publish_to': '',
          'flutter': {}
        })
      ]).create();

      await expectValidationDeprecated(pubspecTypo);
    });

    test('has different keys which are likely not typos', () async {
      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'version': '1.0.0',
          'email': 'my@email.com',
          'maintainer': 'Garett Tok',
          'assets': '../relative/path'
        })
      ]).create();

      await expectValidationDeprecated(pubspecTypo);
    });
  });

  group('should has warnings if it', () {
    setUp(d.validPackage().create);

    test('contains typos', () async {
      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependecies': {},
        })
      ]).create();

      await expectValidationDeprecated(pubspecTypo, warnings: isNotEmpty);
    });

    test('contains typos but does not issue too many warnings', () async {
      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependecies': {},
          'avthor': 'Garett Tok',
          'descripton': 'This is a package',
          'homepagd': 'https://pub.dev/packages/myapp',
          'documentat1on': 'here'
        })
      ]).create();

      await expectValidationDeprecated(
        pubspecTypo,
        warnings: hasLength(lessThanOrEqualTo(3)),
      );
    });
  });
}
