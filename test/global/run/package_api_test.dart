// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('an immutable application sees a file: package config', () async {
    await servePackages((builder) {
      builder.serve('bar', '1.0.0');

      builder.serve('foo', '1.0.0', deps: {
        'bar': '1.0.0'
      }, contents: [
        d.dir('bin', [
          d.file('script.dart', """
import 'dart:isolate';

main() async {
  print(await Isolate.packageRoot);
  print(await Isolate.packageConfig);
  print(await Isolate.resolvePackageUri(
      Uri.parse('package:foo/resource.txt')));
  print(await Isolate.resolvePackageUri(
      Uri.parse('package:bar/resource.txt')));
}
""")
        ])
      ]);
    });

    await runPub(args: ['global', 'activate', 'foo']);

    var pub = await pubRun(global: true, args: ['foo:script']);

    expect(pub.stdout, emits('null'));

    var packageConfigPath =
        p.join(d.sandbox, cachePath, 'global_packages/foo/.packages');
    expect(pub.stdout, emits(p.toUri(packageConfigPath).toString()));

    var fooResourcePath = p.join(
        globalPackageServer.pathInCache('foo', '1.0.0'), 'lib/resource.txt');
    expect(pub.stdout, emits(p.toUri(fooResourcePath).toString()));

    var barResourcePath = p.join(
        globalPackageServer.pathInCache('bar', '1.0.0'), 'lib/resource.txt');
    expect(pub.stdout, emits(p.toUri(barResourcePath).toString()));
    await pub.shouldExit(0);
  });

  test('a mutable untransformed application sees a file: package root',
      () async {
    await d.dir('foo', [d.libPubspec('foo', '1.0.0')]).create();

    await d.dir(appPath, [
      d.appPubspec({
        'foo': {'path': '../foo'}
      }),
      d.dir('bin', [
        d.file('script.dart', """
import 'dart:isolate';

main() async {
  print(await Isolate.packageRoot);
  print(await Isolate.packageConfig);
  print(await Isolate.resolvePackageUri(
      Uri.parse('package:myapp/resource.txt')));
  print(await Isolate.resolvePackageUri(
      Uri.parse('package:foo/resource.txt')));
}
""")
      ])
    ]).create();

    await runPub(args: ['global', 'activate', '-s', 'path', '.']);

    var pub = await pubRun(global: true, args: ['myapp:script']);

    expect(pub.stdout, emits('null'));

    var packageConfigPath = p.join(d.sandbox, 'myapp/.packages');
    expect(pub.stdout, emits(p.toUri(packageConfigPath).toString()));

    var myappResourcePath = p.join(d.sandbox, 'myapp/lib/resource.txt');
    expect(pub.stdout, emits(p.toUri(myappResourcePath).toString()));

    var fooResourcePath = p.join(d.sandbox, 'foo/lib/resource.txt');
    expect(pub.stdout, emits(p.toUri(fooResourcePath).toString()));
    await pub.shouldExit(0);
  });
}
