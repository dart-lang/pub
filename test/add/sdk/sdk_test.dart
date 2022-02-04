// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  setUp(() async {
    await servePackages((builder) {
      builder.serve('bar', '1.0.0');
    });

    await d.dir('flutter', [
      d.dir('packages', [
        d.dir('foo', [
          d.libDir('foo', 'foo 0.0.1'),
          d.libPubspec('foo', '0.0.1', deps: {'bar': 'any'})
        ])
      ]),
      d.dir('bin/cache/pkg', [
        d.dir(
            'baz', [d.libDir('baz', 'foo 0.0.1'), d.libPubspec('baz', '0.0.1')])
      ]),
      d.file('version', '1.2.3')
    ]).create();
  });

  test("adds an SDK dependency's dependencies", () async {
    await d.appDir({}).create();
    await pubAdd(
        args: ['foo', '--sdk', 'flutter'],
        environment: {'FLUTTER_ROOT': p.join(d.sandbox, 'flutter')});

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependencies': {
          'foo': {'sdk': 'flutter', 'version': '^0.0.1'}
        }
      }),
      d.packagesFile({
        'myapp': '.',
        'foo': p.join(d.sandbox, 'flutter', 'packages', 'foo'),
        'bar': '1.0.0'
      })
    ]).validate();
  });

  test(
      "adds an SDK dependency's dependencies with version constraint specified",
      () async {
    await d.appDir({}).create();
    await pubAdd(
        args: ['foo:0.0.1', '--sdk', 'flutter'],
        environment: {'FLUTTER_ROOT': p.join(d.sandbox, 'flutter')});

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependencies': {
          'foo': {'sdk': 'flutter', 'version': '0.0.1'}
        }
      }),
      d.packagesFile({
        'myapp': '.',
        'foo': p.join(d.sandbox, 'flutter', 'packages', 'foo'),
        'bar': '1.0.0'
      })
    ]).validate();
  });

  test('adds an SDK dependency from bin/cache/pkg', () async {
    await d.appDir({}).create();
    await pubAdd(
        args: ['baz', '--sdk', 'flutter'],
        environment: {'FLUTTER_ROOT': p.join(d.sandbox, 'flutter')});

    await d.dir(appPath, [
      d.packagesFile({
        'myapp': '.',
        'baz': p.join(d.sandbox, 'flutter', 'bin', 'cache', 'pkg', 'baz')
      })
    ]).validate();
  });

  test("fails if the version constraint doesn't match", () async {
    await d.appDir({}).create();
    await pubAdd(
        args: ['foo:^1.0.0', '--sdk', 'flutter'],
        environment: {'FLUTTER_ROOT': p.join(d.sandbox, 'flutter')},
        error: equalsIgnoringWhitespace("""
              Because myapp depends on foo ^1.0.0 from sdk which doesn't match
                any versions, version solving failed.
            """),
        exitCode: exit_codes.DATA);

    await d.appDir({}).validate();
    await d.dir(appPath, [
      d.nothing('.dart_tool/package_config.json'),
      d.nothing('pubspec.lock'),
      d.nothing('.packages'),
    ]).validate();
  });
}
