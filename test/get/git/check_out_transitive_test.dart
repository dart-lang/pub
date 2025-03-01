// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:pub/src/exit_codes.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('checks out packages transitively from Git', () async {
    ensureGit();

    await d.git('foo.git', [
      d.libDir('foo'),
      d.libPubspec(
        'foo',
        '1.0.0',
        deps: {
          'bar': {
            'git':
                p
                    .toUri(p.absolute(d.sandbox, appPath, '../bar.git'))
                    .toString(),
          },
        },
      ),
    ]).create();

    await d.git('bar.git', [
      d.libDir('bar'),
      d.libPubspec('bar', '1.0.0'),
    ]).create();

    await d
        .appDir(
          dependencies: {
            'foo': {
              'git':
                  p
                      .toUri(p.absolute(d.sandbox, appPath, '../foo.git'))
                      .toString(),
            },
          },
        )
        .create();

    await pubGet();

    await d.dir(cachePath, [
      d.dir('git', [
        d.dir('cache', [
          d.gitPackageRepoCacheDir('foo'),
          d.gitPackageRepoCacheDir('bar'),
        ]),
        d.gitPackageRevisionCacheDir('foo'),
        d.gitPackageRevisionCacheDir('bar'),
      ]),
    ]).validate();

    expect(packageSpec('foo'), isNotNull);
    expect(packageSpec('bar'), isNotNull);
  });

  test('cannot have relative git url packages transitively from Git', () async {
    ensureGit();

    await d.git('foo.git', [
      d.libDir('foo'),
      d.libPubspec(
        'foo',
        '1.0.0',
        deps: {
          'bar': {'git': '../bar.git'},
        },
      ),
    ]).create();

    await d.git('bar.git', [
      d.libDir('bar'),
      d.libPubspec('bar', '1.0.0'),
    ]).create();

    await d
        .appDir(
          dependencies: {
            'foo': {
              'git':
                  p
                      .toUri(p.absolute(d.sandbox, appPath, '../foo.git'))
                      .toString(),
            },
          },
        )
        .create();

    await pubGet(
      error: contains(
        '"../bar.git" is a relative path, but this isn\'t a local pubspec.',
      ),
      exitCode: exit_codes.DATA,
    );
  });

  test('can have relative path dependencies transitively from Git', () async {
    ensureGit();

    await d.git('foo.git', [
      d.dir('pkgs', [
        d.dir('foo', [
          d.libPubspec(
            'foo',
            '1.0.0',
            deps: {
              'bar': {'path': '../bar'},
            },
          ),
        ]),
        d.dir('bar', [d.libPubspec('bar', '1.0.0')]),
      ]),
    ]).create();

    await d
        .appDir(
          dependencies: {
            'foo': {
              'git': {
                'url':
                    p
                        .toUri(p.absolute(d.sandbox, appPath, '../foo.git'))
                        .toString(),
                'path': 'pkgs/foo',
              },
            },
          },
        )
        .create();

    await pubGet();
    final lockFile = loadYaml(
      File(p.join(d.sandbox, appPath, 'pubspec.lock')).readAsStringSync(),
    );
    expect(
      dig<String>(lockFile, ['packages', 'bar', 'description', 'path']),
      'pkgs/bar',
      reason: 'Use forward slashes for path',
    );
  });

  test('can have relative path dependencies '
      'to the repo root dir transitively from Git', () async {
    ensureGit();

    await d.git('foo.git', [
      d.dir('foo', [
        d.libPubspec(
          'foo',
          '1.0.0',
          deps: {
            'bar': {'path': '..'},
          },
        ),
      ]),
      d.libPubspec('bar', '1.0.0'),
    ]).create();

    await d
        .appDir(
          dependencies: {
            'foo': {
              'git': {
                'url':
                    p
                        .toUri(p.absolute(d.sandbox, appPath, '../foo.git'))
                        .toString(),
                'path': 'foo/',
              },
            },
          },
        )
        .create();

    await pubGet();
  });

  test('cannot have relative path dependencies transitively from Git '
      'to outside the repo', () async {
    ensureGit();

    await d.git('foo.git', [
      d.libPubspec(
        'foo',
        '1.0.0',
        deps: {
          'bar': {'path': '../bar'},
        },
      ),
    ]).create();

    await d.dir('bar', [d.libPubspec('bar', '1.0.0')]).create();

    await d
        .appDir(
          dependencies: {
            'foo': {
              'git':
                  p
                      .toUri(p.absolute(d.sandbox, appPath, '../foo.git'))
                      .toString(),
            },
          },
        )
        .create();

    await pubGet(
      exitCode: DATA,
      error: contains(
        'Invalid description in the "foo" pubspec on the "bar" dependency: '
        'the path "../bar" cannot refer outside the git repository',
      ),
    );
  });
}
