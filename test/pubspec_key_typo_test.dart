// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'descriptor.dart' as d;
import 'test_pub.dart';

void main() {
  test('normal pubspec passes fine', () async {
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

    await pubGet();
  });

  test('typo in key is detected', () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'deepndencies': {},
      })
    ]).create();

    await pubGet(
        output: contains('deepndencies appears to be an invalid key '
            '- did you mean dependencies?'));
  });
}
