// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:pub/src/io.dart';
import 'package:pub/src/lock_file.dart';
import 'package:pub/src/source/git.dart';
import 'package:pub/src/system_cache.dart';
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('depends on a package in a subdirectory', () async {
    ensureGit();

    var repo = d.git('foo.git', [
      d.dir('subdir', [d.libPubspec('sub', '1.0.0'), d.libDir('sub', '1.0.0')])
    ]);
    await repo.create();

    await d.appDir(
      dependencies: {
        'sub': {
          'git': {'url': '../foo.git', 'path': 'subdir'}
        }
      },
    ).create();

    await pubGet();

    await d.dir(cachePath, [
      d.dir('git', [
        d.dir('cache', [d.gitPackageRepoCacheDir('foo')]),
        d.hashDir('foo', [
          d.dir('subdir', [d.libDir('sub', '1.0.0')])
        ])
      ])
    ]).validate();

    await d.appPackageConfigFile([
      d.packageConfigEntry(
        name: 'sub',
        path: pathInCache('git/foo-${await repo.revParse('HEAD')}/subdir'),
      ),
    ]).validate();
  });

  test('depends on a package in a deep subdirectory', () async {
    ensureGit();

    var repo = d.git('foo.git', [
      d.dir('sub', [
        d.dir('dir%', [d.libPubspec('sub', '1.0.0'), d.libDir('sub', '1.0.0')])
      ])
    ]);
    await repo.create();

    await d.appDir(
      dependencies: {
        'sub': {
          'git': {'url': '../foo.git', 'path': 'sub/dir%25'}
        }
      },
    ).create();

    await pubGet();

    await d.dir(cachePath, [
      d.dir('git', [
        d.dir('cache', [d.gitPackageRepoCacheDir('foo')]),
        d.hashDir('foo', [
          d.dir('sub', [
            d.dir('dir%', [d.libDir('sub', '1.0.0')])
          ])
        ])
      ])
    ]).validate();

    await d.appPackageConfigFile([
      d.packageConfigEntry(
        name: 'sub',
        path: pathInCache('git/foo-${await repo.revParse('HEAD')}/sub/dir%25'),
      ),
    ]).validate();

    final lockFile = LockFile.load(
      p.join(d.sandbox, appPath, 'pubspec.lock'),
      SystemCache().sources,
    );

    expect(
      (lockFile.packages['sub']!.description.description as GitDescription)
          .path,
      'sub/dir%25',
      reason: 'use uris to specify the path relative to the repo',
    );
  });

  group('requires path to be absolute', () {
    test('absolute path', () async {
      await d.appDir(
        dependencies: {
          'sub': {
            'git': {'url': '../foo.git', 'path': '/subdir'}
          }
        },
      ).create();

      await pubGet(
        error: contains(
          'Invalid description in the "myapp" pubspec on the "sub" dependency: The \'path\' field of the description must be a relative path URL.',
        ),
        exitCode: exit_codes.DATA,
      );
    });
    test('scheme', () async {
      await d.appDir(
        dependencies: {
          'sub': {
            'git': {'url': '../foo.git', 'path': 'https://subdir'}
          }
        },
      ).create();

      await pubGet(
        error: contains(
          'Invalid description in the "myapp" pubspec on the "sub" dependency: The \'path\' field of the description must be a relative path URL.',
        ),
        exitCode: exit_codes.DATA,
      );
    });
    test('fragment', () async {
      await d.appDir(
        dependencies: {
          'sub': {
            'git': {'url': '../foo.git', 'path': 'subdir/dir#fragment'}
          }
        },
      ).create();

      await pubGet(
        error: contains(
          'Invalid description in the "myapp" pubspec on the "sub" dependency: The \'path\' field of the description must be a relative path URL.',
        ),
        exitCode: exit_codes.DATA,
      );
    });

    test('query', () async {
      await d.appDir(
        dependencies: {
          'sub': {
            'git': {'url': '../foo.git', 'path': 'subdir/dir?query'}
          }
        },
      ).create();

      await pubGet(
        error: contains(
          'Invalid description in the "myapp" pubspec on the "sub" dependency: The \'path\' field of the description must be a relative path URL.',
        ),
        exitCode: exit_codes.DATA,
      );
    });

    test('authority', () async {
      await d.appDir(
        dependencies: {
          'sub': {
            'git': {
              'url': '../foo.git',
              'path': 'bob:pwd@somewhere.example.com/subdir'
            }
          }
        },
      ).create();

      await pubGet(
        error: contains(
          'Invalid description in the "myapp" pubspec on the "sub" dependency: The \'path\' field of the description must be a relative path URL.',
        ),
        exitCode: exit_codes.DATA,
      );
    });
  });

  test('depends on a package in a deep subdirectory, non-relative uri',
      () async {
    ensureGit();

    var repo = d.git('foo.git', [
      d.dir('sub', [
        d.dir('dir%', [d.libPubspec('sub', '1.0.0'), d.libDir('sub', '1.0.0')])
      ])
    ]);
    await repo.create();

    await d.appDir(
      dependencies: {
        'sub': {
          'git': {
            'url': p.toUri(p.join(d.sandbox, 'foo.git')).toString(),
            'path': 'sub/dir%25'
          }
        }
      },
    ).create();

    await pubGet();

    await d.dir(cachePath, [
      d.dir('git', [
        d.dir('cache', [d.gitPackageRepoCacheDir('foo')]),
        d.hashDir('foo', [
          d.dir('sub', [
            d.dir('dir%', [d.libDir('sub', '1.0.0')])
          ])
        ])
      ])
    ]).validate();

    await d.appPackageConfigFile([
      d.packageConfigEntry(
        name: 'sub',
        path: pathInCache('git/foo-${await repo.revParse('HEAD')}/sub/dir%25'),
      ),
    ]).validate();

    final lockFile = LockFile.load(
      p.join(d.sandbox, appPath, 'pubspec.lock'),
      SystemCache().sources,
    );

    expect(
      (lockFile.packages['sub']!.description.description as GitDescription)
          .path,
      'sub/dir%25',
      reason: 'use uris to specify the path relative to the repo',
    );
  });

  test('depends on multiple packages in subdirectories', () async {
    ensureGit();

    var repo = d.git('foo.git', [
      d.dir(
        'subdir1',
        [d.libPubspec('sub1', '1.0.0'), d.libDir('sub1', '1.0.0')],
      ),
      d.dir(
        'subdir2',
        [d.libPubspec('sub2', '1.0.0'), d.libDir('sub2', '1.0.0')],
      )
    ]);
    await repo.create();

    await d.appDir(
      dependencies: {
        'sub1': {
          'git': {'url': '../foo.git', 'path': 'subdir1'}
        },
        'sub2': {
          'git': {'url': '../foo.git', 'path': 'subdir2'}
        }
      },
    ).create();

    await pubGet();

    await d.dir(cachePath, [
      d.dir('git', [
        d.dir('cache', [d.gitPackageRepoCacheDir('foo')]),
        d.hashDir('foo', [
          d.dir('subdir1', [d.libDir('sub1', '1.0.0')]),
          d.dir('subdir2', [d.libDir('sub2', '1.0.0')])
        ])
      ])
    ]).validate();

    await d.appPackageConfigFile([
      d.packageConfigEntry(
        name: 'sub1',
        path: pathInCache('git/foo-${await repo.revParse('HEAD')}/subdir1'),
      ),
      d.packageConfigEntry(
        name: 'sub2',
        path: pathInCache('git/foo-${await repo.revParse('HEAD')}/subdir2'),
      ),
    ]).validate();
  });

  test('depends on packages in the same subdirectory at different revisions',
      () async {
    ensureGit();

    var repo = d.git('foo.git', [
      d.dir(
        'subdir',
        [d.libPubspec('sub1', '1.0.0'), d.libDir('sub1', '1.0.0')],
      )
    ]);
    await repo.create();
    var oldRevision = await repo.revParse('HEAD');

    deleteEntry(p.join(d.sandbox, 'foo.git', 'subdir'));

    await d.git('foo.git', [
      d.dir(
        'subdir',
        [d.libPubspec('sub2', '1.0.0'), d.libDir('sub2', '1.0.0')],
      )
    ]).commit();
    var newRevision = await repo.revParse('HEAD');

    await d.appDir(
      dependencies: {
        'sub1': {
          'git': {'url': '../foo.git', 'path': 'subdir', 'ref': oldRevision}
        },
        'sub2': {
          'git': {'url': '../foo.git', 'path': 'subdir'}
        }
      },
    ).create();

    await pubGet();

    await d.dir(cachePath, [
      d.dir('git', [
        d.dir('cache', [d.gitPackageRepoCacheDir('foo')]),
        d.dir('foo-$oldRevision', [
          d.dir('subdir', [d.libDir('sub1', '1.0.0')])
        ]),
        d.dir('foo-$newRevision', [
          d.dir('subdir', [d.libDir('sub2', '1.0.0')])
        ])
      ])
    ]).validate();

    await d.appPackageConfigFile([
      d.packageConfigEntry(
        name: 'sub1',
        path: pathInCache('git/foo-$oldRevision/subdir'),
      ),
      d.packageConfigEntry(
        name: 'sub2',
        path: pathInCache('git/foo-$newRevision/subdir'),
      ),
    ]).validate();
  });
}
