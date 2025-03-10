// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('an immutable application sees a file: package config', () async {
    await servePackages()
      ..serve('bar', '1.0.0')
      ..serve(
        'foo',
        '1.0.0',
        deps: {'bar': '1.0.0'},
        contents: [
          d.dir('bin', [
            d.file('script.dart', """
import 'dart:isolate';

main() async {
  print(await Isolate.packageConfig);
  print(await Isolate.resolvePackageUri(
      Uri.parse('package:foo/resource.txt')));
  print(await Isolate.resolvePackageUri(
      Uri.parse('package:bar/resource.txt')));
}
"""),
          ]),
        ],
      );

    await runPub(args: ['global', 'activate', 'foo']);

    final pub = await pubRun(global: true, args: ['foo:script']);

    final packageConfigPath = p.join(
      d.sandbox,
      cachePath,
      'global_packages/foo/.dart_tool/package_config.json',
    );
    expect(pub.stdout, emits(p.toUri(packageConfigPath).toString()));

    final fooResourcePath = p.join(
      globalServer.pathInCache('foo', '1.0.0'),
      'lib/resource.txt',
    );
    expect(pub.stdout, emits(p.toUri(fooResourcePath).toString()));

    final barResourcePath = p.join(
      globalServer.pathInCache('bar', '1.0.0'),
      'lib/resource.txt',
    );
    expect(pub.stdout, emits(p.toUri(barResourcePath).toString()));
    await pub.shouldExit(0);
  });

  test(
    'a mutable untransformed application sees a file: package root',
    () async {
      await d.dir('foo', [d.libPubspec('foo', '1.0.0')]).create();

      await d.dir(appPath, [
        d.appPubspec(
          dependencies: {
            'foo': {'path': '../foo'},
          },
        ),
        d.dir('bin', [
          d.file('script.dart', """
import 'dart:isolate';

main() async {
  print(await Isolate.packageConfig);
  print(await Isolate.resolvePackageUri(
      Uri.parse('package:myapp/resource.txt')));
  print(await Isolate.resolvePackageUri(
      Uri.parse('package:foo/resource.txt')));
}
"""),
        ]),
      ]).create();

      await runPub(args: ['global', 'activate', '-s', 'path', '.']);

      final pub = await pubRun(global: true, args: ['myapp:script']);

      final packageConfigPath = p.join(
        d.sandbox,
        'myapp/.dart_tool/package_config.json',
      );
      expect(pub.stdout, emitsThrough(p.toUri(packageConfigPath).toString()));

      final myappResourcePath = p.join(d.sandbox, 'myapp/lib/resource.txt');
      expect(pub.stdout, emits(p.toUri(myappResourcePath).toString()));

      final fooResourcePath = p.join(d.sandbox, 'foo/lib/resource.txt');
      expect(pub.stdout, emits(p.toUri(fooResourcePath).toString()));
      await pub.shouldExit(0);
    },
  );
}
