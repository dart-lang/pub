// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../test_pub.dart';

void main() {
  test('activating a package from a custom pub server', () async {
    // The default pub server (i.e. pub.dartlang.org).
    await servePackages((builder) {
      builder.serve('baz', '1.0.0');
    });

    // The custom pub server.
    final customServer = await PackageServer.start((builder) {
      Map<String, dynamic> hostedDep(String name, String constraint) => {
            'hosted': {
              'url': builder.serverUrl,
              'name': name,
            },
            'version': constraint,
          };
      builder.serve('foo', '1.0.0', deps: {'bar': hostedDep('bar', 'any')});
      builder.serve('bar', '1.0.0', deps: {'baz': 'any'});
    });

    await runPub(
        args: ['global', 'activate', 'foo', '-u', customServer.url],
        output: allOf([
          contains('Downloading bar 1.0.0...'),
          contains('Downloading baz 1.0.0...'),
          contains('Downloading foo 1.0.0...'),
          contains('Activated foo 1.0.0')
        ]));
  });
}
