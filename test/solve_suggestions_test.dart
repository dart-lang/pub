// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'package:pub/src/io.dart' show escapeShellArgument;
import 'package:pub/src/path.dart' show p;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart';

import 'descriptor.dart' as d;
import 'test_pub.dart';

void main() {
  test('suggests an upgrade to the flutter sdk', () async {
    await d.dir('flutter', [d.flutterVersion('1.2.3')]).create();
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      pubspec: {
        'environment': {'flutter': '>=3.3.0', 'sdk': '^2.17.0'},
      },
    );
    server.handle(
      '/flutterReleases',
      (request) => Response.ok(releasesMockResponse),
    );
    await d.dir(appPath, [
      d.libPubspec('myApp', '1.0.0', deps: {'foo': 'any'}, sdk: '^2.17.0'),
    ]).create();
    await pubGet(
      error: contains('* Try using the Flutter SDK version: 3.3.2.'),
      environment: {
        '_PUB_TEST_SDK_VERSION': '2.17.0',
        'FLUTTER_ROOT': path('flutter'),
        '_PUB_TEST_FLUTTER_RELEASES_URL': '${server.url}/flutterReleases',
        'PUB_ENVIRONMENT': 'flutter_cli',
      },
    );
  });

  test('suggests an upgrade to the dart sdk', () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      pubspec: {
        'environment': {'sdk': '>=2.18.0 <2.18.1'},
      },
    );
    server.handle(
      '/flutterReleases',
      (request) => Response.ok(releasesMockResponse),
    );
    await d.dir(appPath, [
      d.libPubspec('myApp', '1.0.0', deps: {'foo': 'any'}, sdk: '^2.17.0'),
    ]).create();
    await pubGet(
      error: contains('* Try using the Dart SDK version: 2.18.0'),
      environment: {
        '_PUB_TEST_SDK_VERSION': '2.17.0',
        '_PUB_TEST_FLUTTER_RELEASES_URL': '${server.url}/flutterReleases',
      },
    );
  });

  test('suggests an upgrade or downgrade to a package constraint', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0', deps: {'bar': '^2.0.0'});
    server.serve('foo', '0.9.0', deps: {'bar': '^1.0.0'});

    server.serve('bar', '1.0.0');
    server.serve('bar', '2.0.0');

    await d.dir(appPath, [
      d.libPubspec(
        'myApp',
        '1.0.0',
        deps: {'foo': '^1.0.0'},
        devDeps: {'bar': '^1.0.0'},
      ),
    ]).create();
    await pubGet(
      error: allOf([
        contains(
          '* Consider downgrading your constraint on foo: '
          'dart pub add foo:^0.9.0',
        ),
        contains(
          '* Try upgrading your constraint on bar: '
          'dart pub add dev:bar:^2.0.0',
        ),
      ]),
    );
  });

  test('suggests an update to an empty package constraint', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');

    await d.dir(appPath, [
      d.libPubspec('myApp', '1.0.0', deps: {'foo': '>1.0.0 <=0.0.0'}),
    ]).create();
    await pubGet(
      error: allOf([
        contains(
          '* Try updating your constraint on foo: dart pub add foo:^1.0.0',
        ),
      ]),
    );
  });

  test(
    'suggests an update to a package constraint in a workspace member',
    () async {
      final server = await servePackages();
      server.serve('foo', '1.0.0', deps: {'bar': '^2.0.0'});
      server.serve('foo', '0.9.0', deps: {'bar': '^1.0.0'});
      server.serve('bar', '1.0.0');
      server.serve('bar', '2.0.0');

      await d.dir(appPath, [
        d.libPubspec(
          'myApp',
          '1.0.0',
          extras: {
            'workspace': ['pkgs/a'],
          },
          sdk: '^3.5.0',
        ),
        d.dir('pkgs', [
          d.dir('a', [
            d.libPubspec(
              'a',
              '1.0.0',
              deps: {'foo': '^1.0.0'},
              devDeps: {'bar': '^1.0.0'},
              resolutionWorkspace: true,
            ),
          ]),
        ]),
      ]).create();

      final packageDir = escapeShellArgument(p.join('pkgs', 'a'));
      await pubGet(
        args: ['--directory', p.join('pkgs', 'a')],
        error: allOf([
          contains(
            '* Try upgrading your constraint on bar: '
            'dart pub add --directory $packageDir dev:bar:^2.0.0',
          ),
          contains(
            '* Consider downgrading your constraint on foo: '
            'dart pub add --directory $packageDir foo:^0.9.0',
          ),
        ]),
        environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      );
    },
  );

  test(
    'suggests one upgrade for a package constrained across a workspace',
    () async {
      final server = await servePackages();
      server.serve('foo', '1.0.0', deps: {'bar': '^2.0.0'});
      server.serve('bar', '1.0.0');
      server.serve('bar', '2.0.0');

      await d.dir(appPath, [
        d.libPubspec(
          'myApp',
          '1.0.0',
          deps: {'foo': '^1.0.0', 'bar': '^1.0.0'},
          extras: {
            'workspace': ['pkgs/a'],
          },
          sdk: '^3.5.0',
        ),
        d.dir('pkgs', [
          d.dir('a', [
            d.libPubspec(
              'a',
              '1.0.0',
              deps: {'bar': '^1.0.0'},
              resolutionWorkspace: true,
            ),
          ]),
        ]),
      ]).create();

      await pubGet(
        error: matches(
          RegExp(
            r'^\* Try an upgrade of your constraints: '
            r'dart pub upgrade --major-versions bar$',
            multiLine: true,
          ),
        ),
        environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      );
    },
  );

  test('serializes workspace member path suggestions from cwd', () async {
    await d.dir(appPath, [
      d.libPubspec(
        'myApp',
        '1.0.0',
        extras: {
          'workspace': ['pkgs/a'],
        },
        sdk: '^3.5.0',
      ),
      d.dir('pkgs', [
        d.dir('a', [
          d.dir('lib'),
          d.libPubspec(
            'a',
            '1.0.0',
            deps: {
              'bar': {'path': '../bar', 'version': '^1.0.0'},
            },
            resolutionWorkspace: true,
          ),
        ]),
        d.dir('bar', [d.libPubspec('bar', '2.0.0')]),
      ]),
    ]).create();

    final packageDir = escapeShellArgument('..');
    await pubGet(
      workingDirectory: p.join(d.sandbox, appPath, 'pkgs', 'a', 'lib'),
      error: contains(
        '* Try updating the following constraints: '
        'dart pub add --directory $packageDir '
        'bar:\'{"version":"^2.0.0","path":"../../bar"}\'',
      ),
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
    );

    await pubAdd(
      args: [
        '--directory',
        '..',
        'bar:{"version":"^2.0.0","path":"../../bar"}',
      ],
      workingDirectory: p.join(d.sandbox, appPath, 'pkgs', 'a', 'lib'),
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      output: contains('Changed 1 dependency in'),
    );

    await d.dir(appPath, [
      d.dir('pkgs', [
        d.dir('a', [
          d.libPubspec(
            'a',
            '1.0.0',
            deps: {
              'bar': {'path': '../bar', 'version': '^2.0.0'},
            },
            resolutionWorkspace: true,
          ),
        ]),
      ]),
    ]).validate();
  });

  test(
    'preserves a dependency source when suggesting a workspace member version',
    () async {
      final server = await startPackageServer();

      await d.dir(appPath, [
        d.libPubspec(
          'myApp',
          '1.0.0',
          deps: {
            'a': {'version': '^2.0.0', 'hosted': server.url},
          },
          extras: {
            'workspace': ['pkgs/a'],
          },
          sdk: '^3.5.0',
        ),
        d.dir('pkgs', [
          d.dir('a', [d.libPubspec('a', '1.0.0', resolutionWorkspace: true)]),
        ]),
      ]).create();

      await pubGet(
        error: contains(
          '* Consider downgrading your constraint on a: dart pub add '
          'a:\'{"version":"^1.0.0","hosted":"${server.url}"}\'',
        ),
        environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      );
    },
  );

  test('suggests updates to multiple packages', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0', deps: {'bar': '2.0.0'});
    server.serve('bar', '1.0.0', deps: {'foo': '2.0.0'});
    server.serve('foo', '2.0.0', deps: {'bar': '2.0.0'});
    server.serve('bar', '2.0.0', deps: {'foo': '2.0.0'});

    await d.dir(appPath, [
      d.libPubspec(
        'myApp',
        '1.0.0',
        deps: {'foo': '1.0.0'},
        devDeps: {'bar': '1.0.0'},
      ),
    ]).create();
    await pubGet(
      error: contains(
        '* Try updating the following constraints: '
        'dart pub add dev:bar:^2.0.0 foo:^2.0.0',
      ),
    );
  });

  test(
    'suggests a major upgrade if more than 5 needs to be upgraded',
    () async {
      final server = await servePackages();
      server.serve('foo', '1.0.0', deps: {'bar': '2.0.0'});
      server.serve('bar', '1.0.0', deps: {'foo': '2.0.0'});
      server.serve('foo', '2.0.0', deps: {'bar': '2.0.0'});
      server.serve('bar', '2.0.0', deps: {'foo': '2.0.0'});
      server.serve('foo1', '1.0.0', deps: {'bar1': '2.0.0'});
      server.serve('bar1', '1.0.0', deps: {'foo1': '2.0.0'});
      server.serve('foo1', '2.0.0', deps: {'bar1': '2.0.0'});
      server.serve('bar1', '2.0.0', deps: {'foo1': '2.0.0'});
      server.serve('foo2', '1.0.0', deps: {'bar2': '2.0.0'});
      server.serve('bar2', '1.0.0', deps: {'foo2': '2.0.0'});
      server.serve('foo2', '2.0.0', deps: {'bar2': '2.0.0'});
      server.serve('bar2', '2.0.0', deps: {'foo2': '2.0.0'});

      await d.dir(appPath, [
        d.libPubspec(
          'myApp',
          '1.0.0',
          deps: {
            'foo': '1.0.0',
            'bar': '1.0.0',
            'foo1': '1.0.0',
            'bar1': '1.0.0',
            'foo2': '1.0.0',
            'bar2': '1.0.0',
          },
        ),
      ]).create();
      await pubGet(
        args: ['--directory', appPath],
        workingDirectory: d.sandbox,
        error: contains(
          '* Try an upgrade of your constraints: '
          'dart pub upgrade --directory $appPath --major-versions '
          'bar bar1 bar2 foo foo1 foo2',
        ),
      );
    },
  );

  test(
    'does not suggest versioned path descriptors for workspace members',
    () async {
      await d.dir(appPath, [
        d.libPubspec(
          'myApp',
          '1.0.0',
          deps: {
            'a': {'path': 'pkgs/a', 'version': '^2.0.0'},
          },
          extras: {
            'workspace': ['pkgs/a'],
          },
          sdk: '^3.5.0',
        ),
        d.dir('pkgs', [
          d.dir('a', [d.libPubspec('a', '1.0.0', resolutionWorkspace: true)]),
        ]),
      ]).create();

      await pubGet(
        error: allOf([
          contains(
            'Because myApp depends on both a ^2.0.0 from path and a, '
            'version solving failed.',
          ),
          isNot(contains('You can try')),
        ]),
        environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      );
    },
  );

  test('suggests upgrades to non-default servers', () async {
    final server = await servePackages();
    final server2 = await startPackageServer();
    server.serve(
      'foo',
      '1.0.0',
      deps: {
        'bar': {'version': '2.0.0', 'hosted': server2.url},
      },
    );

    server2.serve('bar', '1.0.0');
    server2.serve('bar', '2.0.0');

    await d.dir(appPath, [
      d.libPubspec(
        'myApp',
        '1.0.0',
        deps: {
          'foo': '^1.0.0',
          'bar': {'version': '^1.0.0', 'hosted': server2.url},
        },
      ),
    ]).create();
    await pubGet(
      error: contains(
        '* Try upgrading your constraint on bar: dart pub add '
        'bar:\'{"version":"^2.0.0","hosted":"${server2.url}"}\'',
      ),
    );
    await pubAdd(args: ['bar:{"version":"^2.0.0","hosted":"${server2.url}"}']);
    await d.dir(appPath, [
      d.libPubspec(
        'myApp',
        '1.0.0',
        deps: {
          'foo': '^1.0.0',
          'bar': {'version': '^2.0.0', 'hosted': server2.url},
        },
      ),
    ]).validate();
  });
}

const releasesMockResponse = '''
{
  "base_url": "https://storage.googleapis.com/flutter_infra_release/releases",
  "current_release": {
    "beta": "096162697a9cdc79f4e47f7230d70935fa81fd24",
    "dev": "13a2fb10b838971ce211230f8ffdd094c14af02c",
    "stable": "e3c29ec00c9c825c891d75054c63fcc46454dca1"
  },
  "releases": [
    {
      "hash": "e3c29ec00c9c825c891d75054c63fcc46454dca1",
      "channel": "stable",
      "version": "3.3.2",
      "dart_sdk_version": "2.18.1",
      "dart_sdk_arch": "x64",
      "release_date": "2022-09-14T15:06:55.724077Z",
      "archive": "stable/linux/flutter_linux_3.3.2-stable.tar.xz",
      "sha256": "a733a75ae07c42b2059a31fc9d64fabfae5dccd15770fa6b7f290e3f5f9c98e8"
    },
    {
      "hash": "4f9d92fbbdf072a70a70d2179a9f87392b94104c",
      "channel": "stable",
      "version": "3.3.1",
      "dart_sdk_version": "2.18.0",
      "dart_sdk_arch": "x64",
      "release_date": "2022-09-07T15:30:42.283999Z",
      "archive": "stable/linux/flutter_linux_3.3.1-stable.tar.xz",
      "sha256": "7cbcff0230affbe07a5ce82298044ac437e96aeba69f83656f9ed9a910a392e7"
    },
    {
      "hash": "ffccd96b62ee8cec7740dab303538c5fc26ac543",
      "channel": "stable",
      "version": "3.3.0",
      "dart_sdk_version": "2.18.0",
      "dart_sdk_arch": "x64",
      "release_date": "2022-08-30T17:22:12.916008Z",
      "archive": "stable/linux/flutter_linux_3.3.0-stable.tar.xz",
      "sha256": "a92a27aa6d4454d7a1cf9f8a0a56e0e5d6865f2cfcd21cf52e57f7922ad5d504"
    },
    {
      "hash": "096162697a9cdc79f4e47f7230d70935fa81fd24",
      "channel": "beta",
      "version": "3.3.0-0.5.pre",
      "dart_sdk_version": "2.18.0 (build 2.18.0-271.7.beta)",
      "dart_sdk_arch": "x64",
      "release_date": "2022-08-23T17:03:21.525151Z",
      "archive": "beta/linux/flutter_linux_3.3.0-0.5.pre-beta.tar.xz",
      "sha256": "8e07158a64a8ce79f9169cffe4ff23a486bdabb29401f13177672fae18de52d2"
    }
  ]
}
''';
