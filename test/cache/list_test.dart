// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as path;

import '../descriptor.dart' as d;
import '../test_pub.dart';

main() {
  hostedDir(package) {
    return path.join(
        sandboxDir, cachePath, "hosted", "pub.dartlang.org", package);
  }

  integration('running pub cache list when there is no cache', () {
    schedulePub(args: ['cache', 'list'], output: '{"packages":{}}');
  });

  integration('running pub cache list on empty cache', () {
    // Set up a cache.
    d.dir(cachePath, [
      d.dir('hosted', [d.dir('pub.dartlang.org', [])])
    ]).create();

    schedulePub(args: ['cache', 'list'], outputJson: {"packages": {}});
  });

  integration('running pub cache list', () {
    // Set up a cache.
    d.dir(cachePath, [
      d.dir('hosted', [
        d.dir('pub.dartlang.org', [
          d.dir("foo-1.2.3", [d.libPubspec("foo", "1.2.3"), d.libDir("foo")]),
          d.dir("bar-2.0.0", [d.libPubspec("bar", "2.0.0"), d.libDir("bar")])
        ])
      ])
    ]).create();

    schedulePub(args: [
      'cache',
      'list'
    ], outputJson: {
      "packages": {
        "bar": {
          "2.0.0": {"location": hostedDir('bar-2.0.0')}
        },
        "foo": {
          "1.2.3": {"location": hostedDir('foo-1.2.3')}
        }
      }
    });
  });

  integration('includes packages containing deps with bad sources', () {
    // Set up a cache.
    d.dir(cachePath, [
      d.dir('hosted', [
        d.dir('pub.dartlang.org', [
          d.dir("foo-1.2.3", [
            d.libPubspec("foo", "1.2.3", deps: {
              "bar": {"bad": "bar"}
            }),
            d.libDir("foo")
          ])
        ])
      ])
    ]).create();

    schedulePub(args: [
      'cache',
      'list'
    ], outputJson: {
      "packages": {
        "foo": {
          "1.2.3": {"location": hostedDir('foo-1.2.3')}
        }
      }
    });
  });
}
