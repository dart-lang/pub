// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:pub_semver/pub_semver.dart';

import '../descriptor.dart' as d;
import '../golden_file.dart';
import '../test_pub.dart';

Future<void> pipeline(
  GoldenTestContext context,
  List<_PackageVersion> upgrades,
) async {
  await context.run(['__experimental-dependency-services', 'list']);
  await context.run(['__experimental-dependency-services', 'report']);

  final input = json.encode({
    'dependencyChanges': upgrades,
  });

  await context
      .run(['__experimental-dependency-services', 'apply'], stdin: input);
}

Future<void> main() async {
  testWithGolden('Removing transitive', (context) async {
    await servePackages((builder) => builder
      ..serve('foo', '1.2.3', deps: {'transitive': '^1.0.0'})
      ..serve('foo', '2.2.3')
      ..serve('transitive', '1.0.0'));

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {
          'foo': '^1.0.0',
        },
      })
    ]).create();
    await pubGet();
    await pipeline(context, [
      _PackageVersion('foo', Version.parse('2.2.3')),
      _PackageVersion('transitive', null)
    ]);
  });

  testWithGolden('Adding transitive', (context) async {
    await servePackages((builder) => builder
      ..serve('foo', '1.2.3')
      ..serve('foo', '2.2.3', deps: {'transitive': '^1.0.0'})
      ..serve('transitive', '1.0.0'));

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {
          'foo': '^1.0.0',
        },
      })
    ]).create();
    await pubGet();
    await pipeline(context, [
      _PackageVersion('foo', Version.parse('2.2.3')),
      _PackageVersion('transitive', Version.parse('1.0.0'))
    ]);
  });
}

class _PackageVersion {
  String name;
  Version? version;
  _PackageVersion(this.name, this.version);

  Map<String, Object?> toJson() => {
        'name': name,
        'version': version?.toString(),
      };
}
