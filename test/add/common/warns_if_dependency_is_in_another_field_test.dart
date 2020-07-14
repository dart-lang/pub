// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test(
      'warns if user is adding a dependency already present in dev_dependencies',
      () async {
    await servePackages((builder) => builder.serve('foo', '1.2.3'));

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dev_dependencies': {'foo': '1.2.3'}
      })
    ]).create();

    await pubAdd(
        args: ['foo:1.2.3'],
        error: contains('foo is already in dev_dependencies.'),
        exitCode: exit_codes.USAGE);
  });

  test(
      'warns if user is adding a dev dependency already present in dependencies',
      () async {
    await servePackages((builder) => builder.serve('foo', '1.2.3'));

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependencies': {'foo': '1.2.3'}
      })
    ]).create();

    await pubAdd(
        args: ['foo:1.2.3', '--dev'],
        error: contains('foo is already in dependencies. '),
        exitCode: exit_codes.USAGE);
  });
}
