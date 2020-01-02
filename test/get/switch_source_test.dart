// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE d.file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('re-gets a package if its source has changed', () async {
    await servePackages((builder) => builder.serve('foo', '1.2.3'));

    await d.dir('foo',
        [d.libDir('foo', 'foo 0.0.1'), d.libPubspec('foo', '0.0.1')]).create();

    await d.appDir({
      'foo': {'path': '../foo'}
    }).create();

    await pubGet();

    await d.appPackagesFile({'foo': '../foo'}).validate();
    await d.appDir({'foo': 'any'}).create();

    await pubGet();

    await d.appPackagesFile({'foo': '1.2.3'}).validate();
  });
}
