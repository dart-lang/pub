// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'descriptor.dart' as d;
import 'test_pub.dart';

void main() {
  test('package_config.json file is created', () async {
    await servePackages()
      ..serve(
        'foo',
        '1.2.3',
        deps: {'baz': '2.2.2'},
        sdk: '^3.5.0',
        pubspec: {
          // dev_dependencies of non-workspace packages should not be listed
          // in the package_graph.
          'dev_dependencies': {'test': '^1.0.0'},
        },
      )
      ..serve(
        'bar',
        '3.2.1',
        sdk: '^3.5.0',
      )
      ..serve(
        'baz',
        '2.2.2',
        sdk: '^3.5.0',
        deps: {'bar': '3.2.1'},
        contents: [d.dir('lib', [])],
      )
      ..serve(
        'test',
        '1.0.0',
        sdk: '^3.5.0',
      )
      ..serve(
        'test',
        '2.0.0',
        sdk: '^3.5.0',
      );

    await d.dir('boo', [
      d.libPubspec(
        'boo',
        '2.0.0',
        sdk: '^3.5.0',
        deps: {'bar': 'any'},
        devDeps: {'test': '^1.0.0'},
      ),
    ]).create();

    await d.dir(appPath, [
      d.appPubspec(
        dependencies: {
          'foo': '1.2.3',
          'boo': {'path': '../boo'},
        },
        extras: {
          'environment': {
            'sdk': '^3.5.0',
          },
          'dev_dependencies': {'test': '^2.0.0'},
          'workspace': ['helper/'],
        },
      ),
      d.dir('helper', [
        d.libPubspec(
          'helper',
          '2.0.0',
          resolutionWorkspace: true,
        ),
      ]),
    ]).create();

    await pubGet(
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
    );

    final packageGraph = jsonDecode(
      File(p.join(d.sandbox, packageGraphFilePath)).readAsStringSync(),
    );
    expect(packageGraph, {
      'roots': ['helper', 'myapp'],
      'packages': [
        {
          'name': 'myapp',
          'version': '0.0.0',
          'dependencies': ['boo', 'foo'],
          'devDependencies': ['test'],
        },
        {
          'name': 'helper',
          'version': '2.0.0',
          'dependencies': <Object?>[],
          'devDependencies': <Object?>[],
        },
        {'name': 'test', 'version': '2.0.0', 'dependencies': <Object?>[]},
        {
          'name': 'boo',
          'version': '2.0.0',
          'dependencies': ['bar'],
        },
        {
          'name': 'foo',
          'version': '1.2.3',
          'dependencies': ['baz'],
        },
        {'name': 'bar', 'version': '3.2.1', 'dependencies': <Object?>[]},
        {
          'name': 'baz',
          'version': '2.2.2',
          'dependencies': ['bar'],
        }
      ],
      'configVersion': 1,
    });
  });
}
