// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test(
      'Versions inside a tag_pattern dependency can depend on versions from '
      'another commit', () async {
    ensureGit();
    await d.git('foo.git', [
      d.libPubspec(
        'foo',
        '1.0.0',
        sdk: '^3.7.0',
        deps: {
          'bar': {
            'git': {'url': p.join(d.sandbox, 'bar'), 'tag_pattern': '*'},
            'version': '^2.0.0',
          },
        },
      ),
    ]).create();
    await d.git('foo.git', []).tag('a');

    await d.git('foo.git', [
      d.libPubspec(
        'foo',
        '2.0.0',
        sdk: '^3.7.0',
        deps: {
          'bar': {
            'git': {'url': p.join(d.sandbox, 'bar.git'), 'tag_pattern': '*'},
            'version': '^1.0.0',
          },
        },
      ),
    ]).commit();
    await d.git('foo.git', []).tag('b');

    await d.git('bar.git', [
      d.libPubspec(
        'bar',
        '1.0.0',
        sdk: '^3.7.0',
        deps: {
          'foo': {
            'git': {'url': p.join(d.sandbox, 'bar.git'), 'tag_pattern': '*'},
            'version': '^2.0.0',
          },
        },
      ),
    ]).create();
    await d.git('bar.git', []).tag('a');

    await d.git('bar.git', [
      d.libPubspec(
        'bar',
        '2.0.0',
        sdk: '^3.7.0',
        deps: {
          'foo': {
            'git': {'url': p.join(d.sandbox, 'foo.git'), 'tag_pattern': '*'},
            'version': '^1.0.0',
          },
        },
      ),
    ]).commit();
    await d.git('bar.git', []).tag('b');

    await d.appDir(
      dependencies: {
        'foo': {
          'git': {'url': p.join(d.sandbox, 'foo.git'), 'tag_pattern': '*'},
          'version': '^1.0.0',
        },
      },
      pubspec: {
        'environment': {'sdk': '^3.7.0'},
      },
    ).create();

    await pubGet(
      output: allOf(
        contains('+ foo 1.0.0'),
        contains('+ bar 2.0.0'),
      ),
      environment: {
        '_PUB_TEST_SDK_VERSION': '3.7.0',
      },
    );
  });

  test(
      'Versions inside a tag_pattern dependency can depend on versions from '
      'another commit, via path-dependencies', () async {
    ensureGit();

    await d.git('repo.git', [
      d.dir('foo', [
        d.libPubspec(
          'foo',
          '1.0.0',
          deps: {
            'bar': {'path': '../bar', 'version': '^2.0.0'},
          },
        ),
      ]),
      d.dir('bar', [
        d.libPubspec(
          'bar',
          '2.0.0',
          deps: {
            'foo': {'path': '../foo', 'version': '^1.0.0'},
          },
        ),
      ]),
    ]).create();
    await d.git('repo.git', []).tag('a');
    await d.git('repo.git', [
      d.dir('foo', [
        d.libPubspec(
          'foo',
          '2.0.0',
          deps: {
            'bar': {'path': '../bar', 'version': '^2.0.0'},
          },
        ),
      ]),
      d.dir('bar', [
        d.libPubspec(
          'bar',
          '1.0.0',
          deps: {
            'foo': {'path': '../foo', 'version': '^1.0.0'},
          },
        ),
      ]),
    ]).commit();
    await d.git('repo.git', []).tag('b');

    await d.appDir(
      dependencies: {
        'foo': {
          'git': {'url': '../repo.git', 'tag_pattern': '*', 'path': 'foo'},
          'version': '^1.0.0',
        },
      },
      pubspec: {
        'environment': {'sdk': '^3.7.0'},
      },
    ).create();

    await pubGet(
      output: allOf(
        contains('+ foo 1.0.0'),
        contains('+ bar 2.0.0'),
      ),
      environment: {
        '_PUB_TEST_SDK_VERSION': '3.7.0',
      },
    );
  });
}
