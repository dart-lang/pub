// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';
import '../descriptor.dart' as d;
import '../golden_file.dart';
import '../test_pub.dart';

/// Try running 'pub outdated' with a number of different sets of arguments.
///
/// Compare the output to the file in goldens/$[name].
Future<void> variations(String name) async {
  final buffer = StringBuffer();
  for (final args in [
    ['--format=json'],
    ['--format=no-color'],
    ['--format=no-color', '--mark=none'],
    ['--format=no-color', '--up-to-date'],
    ['--format=no-color', '--pre-releases'],
    ['--format=no-color', '--no-dev-dependencies'],
  ]) {
    final process = await startPub(args: ['outdated', ...args]);
    await process.shouldExit(0);
    expect(await process.stderr.rest.toList(), isEmpty);
    buffer.writeln([
      '\$ pub outdated ${args.join(' ')}',
      ...await process.stdout.rest.toList()
    ].join('\n'));
    buffer.write('\n');
  }
  // The easiest way to update the golden files is to delete them and rerun the
  // test.
  expectMatchesGoldenFile(buffer.toString(), 'test/outdated/goldens/$name.txt');
}

Future<void> main() async {
  test('no dependencies', () async {
    await d.appDir().create();
    await pubGet();
    await variations('no_dependencies');
  });

  test('newer versions available', () async {
    await servePackages((builder) => builder
      ..serve('foo', '1.2.3', deps: {'transitive': '^1.0.0'})
      ..serve('bar', '1.0.0')
      ..serve('builder', '1.2.3', deps: {'transitive': '^1.0.0'})
      ..serve('transitive', '1.2.3'));

    await d.dir('local_package', [
      d.libDir('local_package'),
      d.libPubspec('local_package', '0.0.1')
    ]).create();

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {
          'foo': '^1.0.0',
          'bar': '^1.0.0',
          'local_package': {'path': '../local_package'}
        },
        'dev_dependencies': {'builder': '^1.0.0'},
      })
    ]).create();
    await pubGet();
    globalPackageServer.add((builder) => builder
      ..serve('foo', '1.3.0', deps: {'transitive': '>=1.0.0<3.0.0'})
      ..serve('foo', '2.0.0',
          deps: {'transitive': '>=1.0.0<3.0.0', 'transitive2': '^1.0.0'})
      ..serve('foo', '3.0.0', deps: {'transitive': '^2.0.0'})
      ..serve('builder', '1.3.0', deps: {'transitive': '^1.0.0'})
      ..serve('builder', '2.0.0',
          deps: {'transitive': '^1.0.0', 'transitive3': '^1.0.0'})
      ..serve('builder', '3.0.0-alpha', deps: {'transitive': '^1.0.0'})
      ..serve('transitive', '1.3.0')
      ..serve('transitive', '2.0.0')
      ..serve('transitive2', '1.0.0')
      ..serve('transitive3', '1.0.0'));
    await variations('newer_versions');
  });
}
