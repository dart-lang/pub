import 'dart:io';

import 'package:pub/src/path.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() async {
  test(
    'Detects and warns about old cache dir',
    skip: !Platform.isWindows,
    () async {
      await d.dir('APPDATA', [
        d.dir('Pub', [d.dir('Cache')]),
      ]).create();
      final server = await servePackages();
      server.serve('foo', '1.0.0');
      await d.appDir(dependencies: {'foo': '^1.0.0'}).create();
      await pubGet(
        warning: contains('Found a legacy Pub cache at'),
        environment: {'APPDATA': d.path('APPDATA')},
      );
      expect(
        File(
          p.join(sandbox, 'APPDATA', 'Pub', 'Cache', 'DEPRECATED.md'),
        ).existsSync(),
        isTrue,
      );
      server.serve('foo', '2.0.0');
      await d.appDir(dependencies: {'foo': '^2.0.0'}).create();
      await pubGet(warning: isNot(contains('Found a legacy Pub cache')));
    },
  );
}
