// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart=2.10

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../golden_file.dart';
import '../test_pub.dart';

Future<void> pipeline(String name, List<_PackageVersion> upgrades) async {
  final buffer = StringBuffer();
  await runPubIntoBuffer(
      ['__experimental-dependency-services', 'list'], buffer);
  await runPubIntoBuffer(
      ['__experimental-dependency-services', 'report'], buffer);

  await runPubIntoBuffer([
    '__experimental-dependency-services',
    'apply',
  ], buffer,
      stdin: json.encode({
        'changes': upgrades
            .map((e) => {'name': e.name, 'version': e.version.toString()})
            .toList()
      }));
  void catIntoBuffer(String path) {
    buffer.writeln('$path:');
    buffer.writeln(File(p.join(d.sandbox, path)).readAsStringSync());
  }

  catIntoBuffer(p.join(appPath, 'pubspec.yaml'));
  catIntoBuffer(p.join(appPath, 'pubspec.lock'));
  expectMatchesGoldenFile(buffer.toString(),
      'test/dependency_services/goldens/dependency_report_$name.txt');
}

Future<void> main() async {
  test('Removing transitive', () async {
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
    await pipeline('removing_transitive', [
      _PackageVersion('foo', Version.parse('2.2.3')),
      _PackageVersion('transitive', null)
    ]);
  });

  test('Adding transitive', () async {
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
    await pipeline('adding_transitive', [
      _PackageVersion('foo', Version.parse('2.2.3')),
      _PackageVersion('transitive', Version.parse('1.0.0'))
    ]);
  });
}

class _PackageVersion {
  String name;
  Version version;
  _PackageVersion(this.name, this.version);
}
