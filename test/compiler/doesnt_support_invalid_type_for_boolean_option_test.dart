// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import '../serve/utils.dart';

main() {
  test("doesn't support invalid type for boolean option", () async {
    await d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "transformers": [
          {
            "\$dart2js": {
              "checked": "foo",
            }
          }
        ]
      }),
      d.dir("web", [d.file("main.dart", "void main() {}")])
    ]).create();

    await pubGet();
    var server = await pubServe();
    await requestShould404("main.dart.js");
    expect(
        server.stderr,
        emitsLines('Build error:\n'
            'Transform Dart2JS on myapp|web/main.dart threw error: '
            'Invalid value for \$dart2js.checked: "foo" '
            '(expected true or false).'));
    await endPubServe();
  });
}
