// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub/src/exit_codes.dart';
import 'package:pub/src/io.dart';
import 'package:pub/src/sdk/sdk_package_config.dart';
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('recompiles a script if the snapshot is out-of-date', () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      contents: [
        d.dir('bin', [d.file('script.dart', "main(args) => print('ok');")]),
      ],
    );

    await runPub(args: ['global', 'activate', 'foo']);

    await d.dir(cachePath, [
      d.dir('global_packages', [
        d.dir('foo', [
          d.dir('bin', [
            d.outOfDateSnapshot('script.dart-$versionSuffix.snapshot-1'),
          ]),
        ]),
      ]),
    ]).create();

    deleteEntry(
      p.join(
        d.dir(cachePath).io.path,
        'global_packages',
        'foo',
        'bin',
        'script.dart-$versionSuffix.snapshot',
      ),
    );
    final pub = await pubRun(global: true, args: ['foo:script']);
    // In the real world this would just print "hello!", but since we collect
    // all output we see the precompilation messages as well.
    expect(pub.stdout, emits('Resolving dependencies...'));
    expect(pub.stdout, emits('Downloading packages...'));
    expect(pub.stdout, emits(startsWith('No dependencies would change in ')));
    expect(pub.stdout, emits('Building package executable...'));
    expect(pub.stdout, emitsThrough('ok'));
    await pub.shouldExit();

    await d.dir(cachePath, [
      d.dir('global_packages', [
        d.dir('foo', [
          d.dir('bin', [
            d.file('script.dart-$versionSuffix.snapshot', contains('ok')),
          ]),
        ]),
      ]),
    ]).validate();
  });

  test('validate resolution before recompilation', () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      deps: {'bar': 'any'},
      contents: [
        d.dir('bin', [
          d.file('foo.dart', 'import "package:bar/bar.dart"; main() => bar();'),
        ]),
      ],
    );

    server.serve(
      'bar',
      '1.0.0',
      contents: [
        d.dir('lib', [d.file('bar.dart', 'bar() => print("original");')]),
      ],
    );

    await runPub(args: ['global', 'activate', 'foo']);

    await runPub(args: ['global', 'run', 'foo'], output: 'original');

    // Serve an updated version of bar, to validate that the recompilation
    // validates content hashes.
    server.serve(
      'bar',
      '1.0.0',
      contents: [
        d.dir('lib', [d.file('foo.dart', 'foo() => print("updated");')]),
      ],
    );

    // Delete the existing download of bar to trigger a redownload.
    Directory(
      p.join(d.sandbox, d.hostedCachePath(port: server.port), 'bar-1.0.0'),
    ).deleteSync(recursive: true);

    await runPub(
      args: ['global', 'run', 'foo'],
      environment: {
        'DART_ROOT': p.join(d.sandbox, 'dart'),
        // Updated sdk version makes the old snapshot obsolete
        '_PUB_TEST_SDK_VERSION': '3.2.1+4',
      },
      output: contains('~ bar 1.0.0 (was 1.0.0)'),
      error: allOf(
        contains(
          'The current activation of `foo` cannot resolve to the same set of '
          'dependencies.',
        ),
        contains(
          "The existing content-hash from pubspec.lock doesn't match "
          'contents for:',
        ),
        contains('Try reactivating the package'),
      ),
      exitCode: DATA,
    );

    await d.dir('dart', [
      d.dir('packages', [
        d.dir('bar', [
          // Doesn't fulfill constraint, but doesn't satisfy pubspec.lock.
          d.libPubspec('bar', '2.0.0', deps: {}),
        ]),
      ]),
    ]).create();
    await runPub(
      args: ['global', 'run', 'foo'],
      environment: {
        'DART_ROOT': p.join(d.sandbox, 'dart'),
        '_PUB_TEST_SDK_VERSION': '3.2.1+4',
      },
      error: allOf(
        contains(
          'The existing content-hash from pubspec.lock doesn\'t match '
          'contents for:',
        ),
        contains(
          'The current activation of `foo` cannot resolve to the same '
          'set of dependencies.',
        ),
        contains('Try reactivating the package'),
      ),
      exitCode: DATA,
    );
  });

  test(
    'validate resolution before recompilation - updated sdk package',
    () async {
      final server = await servePackages();
      server.serve(
        'foo',
        '1.0.0',
        deps: {
          'bar': {'sdk': 'dart', 'version': '^1.0.0'},
        },
        contents: [
          d.dir('bin', [d.file('foo.dart', 'main() => print("foo");')]),
        ],
      );

      await d.dir('dart', [
        d.dir('packages', [
          d.dir('bar', [d.libPubspec('bar', '1.0.0', deps: {})]),
        ]),
        d.sdkPackagesConfig(
          SdkPackageConfig('dart', {
            'bar': SdkPackage('bar', 'packages/bar'),
          }, 1),
        ),
      ]).create();

      await runPub(
        args: ['global', 'activate', 'foo'],
        environment: {'DART_ROOT': p.join(d.sandbox, 'dart')},
      );

      await runPub(
        args: ['global', 'run', 'foo'],
        environment: {'DART_ROOT': p.join(d.sandbox, 'dart')},
        output: 'foo',
      );

      await d.dir('dart', [
        d.dir('packages', [
          d.dir('bar', [
            // Within constraint, but doesn't satisfy pubspec.lock.
            d.libPubspec('bar', '1.2.0', deps: {}),
          ]),
        ]),
      ]).create();

      await runPub(
        args: ['global', 'run', 'foo'],
        environment: {
          'DART_ROOT': p.join(d.sandbox, 'dart'),
          '_PUB_TEST_SDK_VERSION': '3.2.1+4',
        },
        output: contains('> bar 1.2.0 from sdk dart (was 1.0.0 from sdk dart)'),
        error: allOf(
          contains(
            'The current activation of `foo` is not compatible with your '
            'current SDK.',
          ),
          contains('Try reactivating the package'),
        ),
        exitCode: DATA,
      );

      await d.dir('dart', [
        d.dir('packages', [
          d.dir('bar', [
            // Doesn't fulfill constraint.
            d.libPubspec('bar', '2.0.0', deps: {}),
          ]),
        ]),
      ]).create();
      await runPub(
        args: ['global', 'run', 'foo'],
        environment: {
          'DART_ROOT': p.join(d.sandbox, 'dart'),
          '_PUB_TEST_SDK_VERSION': '3.2.1+4',
        },
        error: allOf(
          contains(
            'So, because pub global activate depends on foo 1.0.0 '
            'which depends on bar ^1.0.0 from sdk',
          ),
          contains('The package `foo` as currently activated cannot resolve.'),
          contains('Try reactivating the package'),
        ),
        exitCode: 1,
      );
    },
  );
}
