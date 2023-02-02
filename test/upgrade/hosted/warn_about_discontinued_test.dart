// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('Warns about discontinued dependencies', () async {
    final server = await servePackages()
      ..serve('foo', '1.2.3', deps: {'transitive': 'any'})
      ..serve('transitive', '1.0.0');
    await d.appDir(dependencies: {'foo': '1.2.3'}).create();
    await pubGet();

    server
      ..discontinue('foo')
      ..discontinue('transitive');
    // We warn only about the direct dependency here:
    await pubUpgrade(
      output: '''
Resolving dependencies...
  foo 1.2.3 (discontinued)
  transitive 1.0.0
  No dependencies changed.
  1 package is discontinued.
''',
    );
    server.discontinue('foo', replacementText: 'bar');
    // We warn only about the direct dependency here:
    await pubUpgrade(
      output: '''
Resolving dependencies...
  foo 1.2.3 (discontinued replaced by bar)
  transitive 1.0.0
  No dependencies changed.
  1 package is discontinued.
''',
    );
  });

  test('Warns about discontinued dev_dependencies', () async {
    final server = await servePackages()
      ..serve('foo', '1.2.3', deps: {'transitive': 'any'})
      ..serve('transitive', '1.0.0');

    await d.dir(appPath, [
      d.file('pubspec.yaml', '''
name: myapp
dependencies:

dev_dependencies:
  foo: 1.2.3
environment:
  sdk: '^3.1.2'
''')
    ]).create();
    await pubGet();

    server
      ..discontinue('foo')
      ..discontinue('transitive');

    // We warn only about the direct dependency here:
    await pubUpgrade(
      output: '''
Resolving dependencies...
  foo 1.2.3 (discontinued)
    transitive 1.0.0
  No dependencies changed.
  1 package is discontinued.
''',
    );
    server.discontinue('foo', replacementText: 'bar');
    // We warn only about the direct dependency here:
    await pubUpgrade(
      output: '''
Resolving dependencies...
  foo 1.2.3 (discontinued replaced by bar)
  transitive 1.0.0
  No dependencies changed.
  1 package is discontinued.
''',
    );
  });
}
