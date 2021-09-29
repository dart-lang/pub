// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart=2.10

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  setUp(() => servePackages((b) => b.serve('foo', '1.2.3', pubspec: {
        'environment': {'sdk': '^2.0.0'}
      })));

  forBothPubGetAndUpgrade((command) {
    Future<void> testWith(dynamic dependency) async {
      await d.dir(appPath, [
        d.libPubspec(
          'app',
          '1.0.0',
          deps: {'foo': dependency},
          sdk: '^2.15.0',
        ),
      ]).create();

      await pubCommand(
        command,
        exitCode: 0,
        environment: {'_PUB_TEST_SDK_VERSION': '2.15.0'},
      );

      final lockFile = loadYaml(
        await File(p.join(d.sandbox, appPath, 'pubspec.lock')).readAsString(),
      );

      expect(lockFile['packages']['foo'], {
        'dependency': 'direct main',
        'source': 'hosted',
        'description': {
          'name': 'foo',
          'url': globalPackageServer.url,
        },
        'version': '1.2.3',
      });
    }

    test('supports hosted: <url> syntax', () async {
      return testWith({'hosted': globalPackageServer.url});
    });

    test('supports hosted map without name', () {
      return testWith({
        'hosted': {'url': globalPackageServer.url},
      });
    });

    test('interprets hosted string as name for older versions', () async {
      await d.dir(appPath, [
        d.libPubspec(
          'app',
          '1.0.0',
          deps: {
            'foo': {'hosted': 'foo', 'version': '^1.2.3'}
          },
          sdk: '^2.0.0',
        ),
      ]).create();

      await pubCommand(
        command,
        exitCode: 0,
        environment: {'_PUB_TEST_SDK_VERSION': '2.15.0'},
      );

      final lockFile = loadYaml(
        await File(p.join(d.sandbox, appPath, 'pubspec.lock')).readAsString(),
      );

      expect(lockFile['packages']['foo']['description']['url'],
          globalPackageServer.url);
    });
  });
}
