import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() async {
  test('Detects old cache dir', skip: !Platform.isWindows, () async {
    final legacyCacheLocation =
        p.join(Platform.environment['APPDATA']!, 'Pub', 'Cache');
    final legacyCacheDir = Directory(legacyCacheLocation);
    if (legacyCacheDir.existsSync()) {
      fail('Cannot run test with existing $legacyCacheLocation');
    }
    legacyCacheDir.createSync(recursive: true);
    stdout.writeln('A $legacyCacheLocation ${legacyCacheDir.existsSync()}');
    addTearDown(() => legacyCacheDir.deleteSync(recursive: true));

    final server = await servePackages();
    server.serve('foo', '1.0.0');
    await d.appDir(dependencies: {'foo': '^1.0.0'}).create();
    await pubGet(
      warning: contains('Found a legacy pub cache at $legacyCacheLocation.'),
    );
    expect(
      File(p.join(legacyCacheLocation, 'DEPRECATED.md')).existsSync(),
      isTrue,
    );
    server.serve('foo', '2.0.0');
    await d.appDir(dependencies: {'foo': '^2.0.0'}).create();
    await pubGet(
      warning: isNot(contains('Found a legacy pub cache')),
    );
  });
}
