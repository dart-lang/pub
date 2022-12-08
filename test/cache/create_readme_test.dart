import 'dart:io';

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() async {
  test('PUB_CACHE/README.md gets created by command downloading to pub cache',
      () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');
    await d.appDir().create();
    await pubGet();
    await d.nothing(cachePath).validate();

    await d.appDir(dependencies: {'foo': '1.0.0'}).create();
    await pubGet();
    await d.dir(cachePath, [
      d.file('README.md', contains('https://dart.dev/go/pub-cache'))
    ]).validate();
    File(pathInCache('README.md')).deleteSync();
    // No new download, so 'README.md' doesn't get updated.
    await pubGet();
    await d.dir(cachePath, [d.nothing('README.md')]).validate();
  });

  test('PUB_CACHE/README.md gets created by `dart pub cache clean`', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');
    await d.appDir(dependencies: {'foo': '1.0.0'}).create();
    await pubGet();
    await d.dir(cachePath, [
      d.file('README.md', contains('https://dart.dev/go/pub-cache'))
    ]).validate();
  });
}
