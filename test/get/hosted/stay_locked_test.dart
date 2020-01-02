// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import 'package:pub/src/io.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test(
      'keeps a hosted package locked to the version in the '
      'lockfile', () async {
    await servePackages((builder) => builder.serve('foo', '1.0.0'));

    await d.appDir({'foo': 'any'}).create();

    // This should lock the foo dependency to version 1.0.0.
    await pubGet();

    await d.appPackagesFile({'foo': '1.0.0'}).validate();

    // Delete the .packages file to simulate a new checkout of the application.
    deleteEntry(path.join(d.sandbox, packagesFilePath));

    // Start serving a newer package as well.
    globalPackageServer.add((builder) => builder.serve('foo', '1.0.1'));

    // This shouldn't upgrade the foo dependency due to the lockfile.
    await pubGet();

    await d.appPackagesFile({'foo': '1.0.0'}).validate();
  });
}
