// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:pub/src/entrypoint.dart';
import 'package:pub/src/system_cache.dart';
import 'package:test/test.dart';

import 'descriptor.dart' as d;
import 'test_pub.dart';

void main() {
  test('transitiveDependencies', () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      deps: {
        'transitive': {'hosted': globalServer.url},
      },
      pubspec: {
        'dev_dependencies': {
          'transitive_dev_dep': {'hosted': globalServer.url},
        }, // This should **not** be included.
      },
    );
    server.serve(
      'dev_dep',
      '1.0.0',
      deps: {
        'dev_dep_transitive': {'hosted': globalServer.url},
      },
      pubspec: {
        'dev_dependencies': {
          'transitive_dev_dep': {
            'hosted': globalServer.url,
          }, // This should **not** be included.
        },
      },
    );
    server.serve('dev_dep_transitive', '1.0.0');
    server.serve('transitive', '1.0.0');
    await d
        .appDir(
          dependencies: {
            'foo': {'hosted': globalServer.url},
          },
          pubspec: {
            'dev_dependencies': {
              'dev_dep': {'hosted': globalServer.url},
            },
          },
        )
        .create();
    await pubGet();
    final entrypoint = Entrypoint(
      p.join(d.sandbox, appPath),
      SystemCache(rootDir: p.join(d.sandbox, cachePath)),
    );
    final graph = await entrypoint.packageGraph;

    expect(
      graph
          .transitiveDependencies('foo', followDevDependenciesFromRoots: true)
          .map((p) => p.name),
      {'foo', 'transitive'},
    );

    expect(
      graph
          .transitiveDependencies('foo', followDevDependenciesFromRoots: false)
          .map((p) => p.name),
      {'foo', 'transitive'},
    );

    expect(
      graph
          .transitiveDependencies('myapp', followDevDependenciesFromRoots: true)
          .map((p) => p.name),
      {'myapp', 'foo', 'dev_dep', 'dev_dep_transitive', 'transitive'},
    );

    expect(
      graph
          .transitiveDependencies(
            'myapp',
            followDevDependenciesFromRoots: false,
          )
          .map((p) => p.name),
      {'myapp', 'foo', 'transitive'},
    );
  });
}
