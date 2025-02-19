// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

const _script = """
  import 'dart:isolate';

  main() async {
    print(await Isolate.packageConfig);
    print(await Isolate.resolvePackageUri(
        Uri.parse('package:myapp/resource.txt')));
    print(await Isolate.resolvePackageUri(
        Uri.parse('package:foo/resource.txt')));
  }
""";

void main() {
  test('an untransformed application sees a file: package config', () async {
    await d.dir('foo', [d.libPubspec('foo', '1.0.0')]).create();

    await d.dir(appPath, [
      d.appPubspec(
        dependencies: {
          'foo': {'path': '../foo'},
        },
      ),
      d.dir('bin', [d.file('script.dart', _script)]),
    ]).create();

    await pubGet();
    final pub = await pubRun(args: ['bin/script']);

    expect(
      pub.stdout,
      emitsThrough(
        p
            .toUri(p.join(d.sandbox, 'myapp/.dart_tool/package_config.json'))
            .toString(),
      ),
    );
    expect(
      pub.stdout,
      emits(p.toUri(p.join(d.sandbox, 'myapp/lib/resource.txt')).toString()),
    );
    expect(
      pub.stdout,
      emits(p.toUri(p.join(d.sandbox, 'foo/lib/resource.txt')).toString()),
    );
    await pub.shouldExit(0);
  });

  test('a snapshotted application sees a file: package root', () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      contents: [
        d.dir('bin', [d.file('script.dart', _script)]),
      ],
    );

    await d.dir(appPath, [
      d.appPubspec(dependencies: {'foo': 'any'}),
    ]).create();

    await pubGet();

    final pub = await pubRun(args: ['foo:script']);

    expect(pub.stdout, emitsThrough('Building package executable...'));
    expect(pub.stdout, emits('Built foo:script.'));
    expect(
      pub.stdout,
      emits(
        p
            .toUri(p.join(d.sandbox, 'myapp/.dart_tool/package_config.json'))
            .toString(),
      ),
    );
    expect(
      pub.stdout,
      emits(p.toUri(p.join(d.sandbox, 'myapp/lib/resource.txt')).toString()),
    );
    final fooResourcePath = p.join(
      globalServer.pathInCache('foo', '1.0.0'),
      'lib/resource.txt',
    );
    expect(pub.stdout, emits(p.toUri(fooResourcePath).toString()));
    await pub.shouldExit(0);
  });
}
