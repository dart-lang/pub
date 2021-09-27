// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart=2.10

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../golden_file.dart';
import '../test_pub.dart';

/// Try running 'pub outdated' with a number of different sets of arguments.
///
/// Compare the stdout and stderr output to the file in goldens/$[name].
Future<void> pipeline(String name, List<String> upgrades) async {
  final buffer = StringBuffer();
  await runPubIntoBuffer(
      ['__experimental-dependency-services', 'list'], buffer);
  await runPubIntoBuffer(
      ['__experimental-dependency-services', 'report'], buffer);
  // final reportProcess =
  //     await startPub(args: ['__experimental-dependency-services', 'report']);
  // await reportProcess.exitCode;

  // final report =
  //     json.decode((await reportProcess.stdoutStream().toList()).join('\n'));

  await runPubIntoBuffer([
    '__experimental-dependency-services',
    'apply',
    ...upgrades,
  ], buffer);
  void catIntoBuffer(String path) {
    buffer.writeln('$path:');
    buffer.writeln(File(p.join(d.sandbox, path)).readAsStringSync());
  }

  catIntoBuffer(p.join(appPath, 'pubspec.yaml'));
  catIntoBuffer(p.join(appPath, 'pubspec.lock'));
  // The easiest way to update the golden files is to delete them and rerun the
  // test.
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
    await pipeline('removing_transitive', ['foo:2.2.3', 'transitive']);
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
    await pipeline('adding_transitive', ['foo:2.2.3', 'transitive:1.0.0']);
  });

  // test('newer versions available', () async {
  //   await servePackages((builder) => builder
  //     ..serve('foo', '1.2.3', deps: {'transitive': '^1.0.0'})
  //     ..serve('bar', '1.0.0')
  //     ..serve('builder', '1.2.3', deps: {
  //       'transitive': '^1.0.0',
  //       'dev_trans': '^1.0.0',
  //     })
  //     ..serve('transitive', '1.2.3')
  //     ..serve('dev_trans', '1.0.0'));

  //   await d.dir('local_package', [
  //     d.libDir('local_package'),
  //     d.libPubspec('local_package', '0.0.1')
  //   ]).create();

  //   await d.dir(appPath, [
  //     d.pubspec({
  //       'name': 'app',
  //       'dependencies': {
  //         'foo': '^1.0.0',
  //         'bar': '^1.0.0',
  //         'local_package': {'path': '../local_package'}
  //       },
  //       'dev_dependencies': {'builder': '^1.0.0'},
  //     })
  //   ]).create();
  //   await pubGet();
  //   globalPackageServer.add((builder) => builder
  //     ..serve('foo', '1.3.0',
  //         deps: {'transitive': '>=1.0.0<3.0.0', 'transitive4': '^1.0.0'})
  //     ..serve('foo', '2.0.0',
  //         deps: {'transitive': '>=1.0.0<3.0.0', 'transitive2': '^1.0.0'})
  //     ..serve('foo', '3.0.0', deps: {'transitive': '^2.0.0'})
  //     ..serve('builder', '1.3.0', deps: {'transitive': '^1.0.0'})
  //     ..serve('builder', '2.0.0', deps: {
  //       'transitive': '^1.0.0',
  //       'transitive3': '^1.0.0',
  //       'dev_trans': '^1.0.0'
  //     })
  //     ..serve('builder', '3.0.0-alpha', deps: {'transitive': '^1.0.0'})
  //     ..serve('transitive', '1.3.0')
  //     ..serve('transitive', '2.0.0')
  //     ..serve('transitive2', '1.0.0')
  //     ..serve('transitive3', '1.0.0')
  //     ..serve('transitive4', '1.0.0')
  //     ..serve('dev_trans', '2.0.0'));
  //   await pipeline('newer_versions');
  // });
}
