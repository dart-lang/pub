import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() async {
  test(
    'PUB_CACHE/README.md gets created by command downloading to pub cache',
    () async {
      final server = await servePackages();
      server.serve('foo', '1.0.0');
      await d.appDir().create();
      await pubGet();
      await d.nothing(cachePath).validate();

      await d.appDir(dependencies: {'foo': '1.0.0'}).create();
      await pubGet();
      await d.dir(cachePath, [
        d.file('README.md', contains('https://dart.dev/go/pub-cache')),
      ]).validate();
      File(pathInCache('README.md')).deleteSync();
      // No new download, so 'README.md' doesn't get updated.
      await pubGet();
      await d.dir(cachePath, [d.nothing('README.md')]).validate();
    },
  );

  test('PUB_CACHE/README.md gets created by `dart pub cache clean`', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');
    await d.appDir(dependencies: {'foo': '1.0.0'}).create();
    await pubGet();
    await d.dir(cachePath, [
      d.file('README.md', contains('https://dart.dev/go/pub-cache')),
    ]).validate();
  });

  test('PUB_CACHE/README.md gets created when compiling a snapshot', () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      contents: [d.file('bin/foo.dart', "main() {print('Hello');}")],
    );
    await runPub(args: ['global', 'activate', 'foo']);
    File(p.join(d.sandbox, cachePath, 'README.md')).deleteSync();
    // Replace the created snapshot with one that really doesn't work with the
    // current dart.
    await d.dir(cachePath, [
      d.dir('global_packages', [
        d.dir('foo', [
          d.dir('bin', [d.outOfDateSnapshot('foo.dart-3.1.2+3.snapshot')]),
        ]),
      ]),
    ]).create();
    await runPub(args: ['global', 'run', 'foo'], output: contains('Hello'));
    await d.dir(cachePath, [
      d.file('README.md', contains('https://dart.dev/go/pub-cache')),
    ]).validate();
  });
}
