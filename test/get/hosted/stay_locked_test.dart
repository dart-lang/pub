// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as path;
import 'package:pub/src/io.dart';
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test(
      'keeps a hosted package locked to the version in the '
      'lockfile', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');

    await d.appDir(dependencies: {'foo': 'any'}).create();

    // This should lock the foo dependency to version 1.0.0.
    await pubGet();
    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '1.0.0'),
    ]).validate();

    // Delete the .dart_tool/package_config.json file to simulate a new checkout of the application.
    deleteEntry(path.join(d.sandbox, packageConfigFilePath));

    // Start serving a newer package as well.
    server.serve('foo', '1.0.1');

    // This shouldn't upgrade the foo dependency due to the lockfile.
    await pubGet();

    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '1.0.0'),
    ]).validate();
  });
}
