import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:pub/src/system_cache.dart';
import 'package:pub/src/utils.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() async {
  test('marks a package active on pub get and global activate', () async {
    final server = await servePackages();

    server.serve('foo', '1.0.0');
    server.serve('bar', '1.0.0');

    await runPub(args: ['global', 'activate', 'foo']);

    // Without cached dependencies we don't register the package
    await d.dir('app_none', [d.appPubspec()]).create();

    await d.appDir(dependencies: {'bar': '1.0.0'}).create();

    await d.dir('app_hosted', [
      d.appPubspec(dependencies: {'bar': '^1.0.0'}),
    ]).create();

    await d.git('lib', [d.libPubspec('lib', '1.0.0')]).create();

    await d.dir('app_git', [
      d.appPubspec(
        dependencies: {
          'lib': {'git': '../lib'},
        },
      ),
    ]).create();

    await d.dir('app_path', [
      d.appPubspec(
        dependencies: {
          'lib': {'path': '../lib'},
        },
      ),
    ]).create();

    await pubGet(workingDirectory: p.join(d.sandbox, 'app_none'));
    await pubGet(workingDirectory: p.join(d.sandbox, 'app_hosted'));
    await pubGet(workingDirectory: p.join(d.sandbox, 'app_git'));
    await pubGet(workingDirectory: p.join(d.sandbox, 'app_path'));

    final markingFiles =
        Directory(
          p.join(d.sandbox, cachePath, 'active_roots'),
        ).listSync(recursive: true).whereType<File>().toList();

    expect(markingFiles, hasLength(3));

    for (final file in markingFiles) {
      final uri =
          (jsonDecode(file.readAsStringSync()) as Map)['package_config']
              as String;
      final hash = hexEncode(sha256.convert(utf8.encode(uri)).bytes);
      final hashFileName =
          '${p.basename(p.dirname(file.path))}${p.basename(file.path)}';
      expect(hashFileName, hash);
    }

    expect(markingFiles, hasLength(3));

    expect(SystemCache(rootDir: p.join(d.sandbox, cachePath)).activeRoots(), {
      p.canonicalize(
        p.join(d.sandbox, 'app_hosted', '.dart_tool', 'package_config.json'),
      ),
      p.canonicalize(
        p.join(d.sandbox, 'app_git', '.dart_tool', 'package_config.json'),
      ),

      p.canonicalize(
        p.join(
          d.sandbox,
          cachePath,
          'global_packages',
          'foo',
          '.dart_tool',
          'package_config.json',
        ),
      ),
    });
  });
}
