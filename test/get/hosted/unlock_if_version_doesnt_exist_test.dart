// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:pub/src/io.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('upgrades a locked pub server package with a nonexistent version',
      () async {
    await servePackages((builder) => builder.serve('foo', '1.0.0'));

    await d.appDir({'foo': 'any'}).create();
    await pubGet();
    await d.appPackagesFile({'foo': '1.0.0'}).validate();

    deleteEntry(p.join(d.sandbox, cachePath));

    globalPackageServer.replace((builder) => builder.serve('foo', '1.0.1'));
    await pubGet();
    await d.appPackagesFile({'foo': '1.0.1'}).validate();
  });
}
