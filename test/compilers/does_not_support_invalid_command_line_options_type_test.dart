// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../descriptor.dart' as d;
import '../test_pub.dart';
import '../serve/utils.dart';

main() {
  integration("doesn't support invalid commandLineOptions type", () {
    d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "transformers": [
          {
            "\$dart2js": {
              "commandLineOptions": "foo",
            }
          }
        ]
      }),
      d.dir("web", [d.file("main.dart", "void main() {}")])
    ]).create();

    pubGet();
    var server = pubServe();
    // Make a request first to trigger compilation.
    requestShould404("main.dart.js");
    server.stderr.expect(emitsLines('Build error:\n'
        'Transform Dart2JS on myapp|web/main.dart threw error: '
        'Invalid value for \$dart2js.commandLineOptions: '
        '"foo" (expected list of strings).'));
    endPubServe();
  });
}
