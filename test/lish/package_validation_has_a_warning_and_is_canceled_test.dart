// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('package validation has a warning and is canceled', () async {
    await d.validPackage().create();
    var pkg = packageMap(
      'test_pkg',
      '1.0.0',
      null,
      null,
      {'sdk': defaultSdkConstraint},
    );
    pkg['author'] = 'Natalie Weizenbaum';
    await d.dir(appPath, [
      d.pubspec(pkg),
    ]).create();

    await servePackages();
    var pub = await startPublish(globalServer);

    pub.stdin.writeln('n');
    await pub.shouldExit(exit_codes.DATA);
    expect(pub.stderr, emitsThrough('Package upload canceled.'));
  });
}
