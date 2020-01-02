// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:path/path.dart' as path;

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  String hostedDir(package) {
    return path.join(
        d.sandbox, cachePath, 'hosted', 'pub.dartlang.org', package);
  }

  test('running pub cache list when there is no cache', () async {
    await runPub(args: ['cache', 'list'], output: '{"packages":{}}');
  });

  test('running pub cache list on empty cache', () async {
    // Set up a cache.
    await d.dir(cachePath, [
      d.dir('hosted', [d.dir('pub.dartlang.org', [])])
    ]).create();

    await runPub(args: ['cache', 'list'], outputJson: {'packages': {}});
  });

  test('running pub cache list', () async {
    // Set up a cache.
    await d.dir(cachePath, [
      d.dir('hosted', [
        d.dir('pub.dartlang.org', [
          d.dir('foo-1.2.3', [d.libPubspec('foo', '1.2.3'), d.libDir('foo')]),
          d.dir('bar-2.0.0', [d.libPubspec('bar', '2.0.0'), d.libDir('bar')])
        ])
      ])
    ]).create();

    await runPub(args: [
      'cache',
      'list'
    ], outputJson: {
      'packages': {
        'bar': {
          '2.0.0': {'location': hostedDir('bar-2.0.0')}
        },
        'foo': {
          '1.2.3': {'location': hostedDir('foo-1.2.3')}
        }
      }
    });
  });

  test('includes packages containing deps with bad sources', () async {
    // Set up a cache.
    await d.dir(cachePath, [
      d.dir('hosted', [
        d.dir('pub.dartlang.org', [
          d.dir('foo-1.2.3', [
            d.libPubspec('foo', '1.2.3', deps: {
              'bar': {'bad': 'bar'}
            }),
            d.libDir('foo')
          ])
        ])
      ])
    ]).create();

    await runPub(args: [
      'cache',
      'list'
    ], outputJson: {
      'packages': {
        'foo': {
          '1.2.3': {'location': hostedDir('foo-1.2.3')}
        }
      }
    });
  });
}
