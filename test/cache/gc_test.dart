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

  test('gcing an empty cache behaves well', () async {
    await runPub(
      args: ['cache', 'gc', '--force'],
      output: allOf(
        contains('Found no active projects.'),
        contains('No unused cache entries found.'),
      ),
    );
  });

  test('can gc cache entries', () async {
    final server = await servePackages();

    server.serve('hosted1', '1.0.0');
    server.serve('hosted2', '1.0.0');

    await d.git('git1', [d.libPubspec('git1', '1.0.0')]).create();
    await d.git('git2', [d.libPubspec('git2', '1.0.0')]).create();

    await d.git('git_with_path1', [
      d.dir('pkg', [d.libPubspec('git_with_path1', '1.0.0')]),
    ]).create();
    await d.git('git_with_path2', [
      d.dir('pkg', [d.libPubspec('git_with_path2', '1.0.0')]),
    ]).create();

    await d
        .appDir(
          dependencies: {
            'hosted1': '1.0.0',
            'git1': {'git': '../git1'},
            'git_with_path1': {
              'git': {'url': '../git_with_path1', 'path': 'pkg'},
            },
          },
        )
        .create();
    await pubGet();
    await d
        .appDir(
          dependencies: {
            'hosted2': '1.0.0',
            'git2': {'git': '../git2'},
            'git_with_path2': {
              'git': {'url': '../git_with_path2', 'path': 'pkg'},
            },
          },
        )
        .create();
    await pubGet(output: contains('- hosted1'));

    await runPub(
      args: ['cache', 'gc', '--force'],
      output: allOf(
        matches(
          RegExp(
            RegExp.escape('* ${p.join(d.sandbox, appPath)}'),
            caseSensitive: false,
          ),
        ),
        contains('No unused cache entries found'),
      ),
    );
    await Future<void>.delayed(const Duration(seconds: 2));

    await runPub(
      args: ['cache', 'gc', '--force'],
      output: allOf(
        contains('* ${p.join(d.sandbox, appPath).toLowerCase()}'),
        contains(RegExp('Will recover [0-9]{3} KB.')),
      ),
      silent: allOf([
        contains(RegExp('Deleting directory .*git.*cache/git1-.*')),
        contains(RegExp('Deleting directory .*git.*cache/git_with_path1-.*')),
        contains(RegExp('Deleting directory .*git.*git1-.*')),
        contains(RegExp('Deleting directory .*git.*git_with_path1-.*')),
        contains(
          RegExp('Deleting file .*hosted-hashes.*hosted1-1.0.0.sha256.'),
        ),
        contains(RegExp('Deleting directory .*hosted.*hosted1-1.0.0.')),
        isNot(contains(RegExp('Deleting.*hosted2'))),
        isNot(contains(RegExp('Deleting.*git2'))),
        isNot(contains(RegExp('Deleting.*git_with_path2'))),
      ]),
    );
    expect(
      Directory(
        p.join(d.sandbox, d.hostedCachePath(), 'hosted1-1.0.0'),
      ).existsSync(),
      isFalse,
    );
    expect(
      Directory(
        p.join(d.sandbox, d.hostedCachePath(), 'hosted2-1.0.0'),
      ).existsSync(),
      isTrue,
    );

    expect(
      Directory(
        p.join(d.sandbox, cachePath, 'git'),
      ).listSync().map((f) => p.basename(f.path)),
      {'cache', matches(RegExp('git2.*')), matches(RegExp('git_with_path2.*'))},
    );

    expect(
      Directory(
        p.join(d.sandbox, cachePath, 'git', 'cache'),
      ).listSync().map((f) => p.basename(f.path)),
      {matches(RegExp('git2.*')), matches(RegExp('git_with_path2.*'))},
    );
  });
}
