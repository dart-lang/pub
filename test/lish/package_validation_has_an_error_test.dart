// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('package validation has an error', () async {
    await d.dir(appPath, [
      d.rawPubspec({
        'name': 'test_pkg',
        'homepage': 'https://pub.dev',
        'version': '1.0.0',
        'environment': {'sdk': defaultSdkConstraint}
      }),
    ]).create();

    await servePackages();
    var pub = await startPublish(globalServer);

    await pub.shouldExit(exit_codes.DATA);
    expect(
      pub.stderr,
      emitsThrough('Sorry, your package is missing some '
          "requirements and can't be published yet."),
    );
  });
}
