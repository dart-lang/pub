// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('adds a package from a non-default pub server', () async {
    // Make the default server serve errors. Only the custom server should
    // be accessed.
    await serveErrors();

    var server = await PackageServer.start((builder) {
      builder.serve('foo', '1.2.3');
    });

    await d.appDir({}).create();

    final url = server.url;

    await pubAdd(args: ['foo:1.2.3', '--host-name', 'foo', '--host-url', url]);

    await d.cacheDir({'foo': '1.2.3'}, port: server.port).validate();
    await d.appPackagesFile({'foo': '1.2.3'}).validate();
    await d.appDir({
      'foo': {
        'version': '1.2.3',
        'hosted': {'name': 'foo', 'url': url}
      }
    }).validate();
  });
}
