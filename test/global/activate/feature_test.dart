// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Skip()

import 'package:test/test.dart';

import '../../test_pub.dart';

void main() {
  test('enables default-on features by default', () async {
    await servePackages((builder) {
      builder.serve('foo', '1.0.0', pubspec: {
        'features': {
          'stuff': {
            'dependencies': {'bar': '1.0.0'}
          },
          'things': {
            'default': false,
            'dependencies': {'baz': '1.0.0'}
          }
        }
      });

      builder.serve('bar', '1.0.0');
      builder.serve('baz', '1.0.0');
    });

    await runPub(args: ['global', 'activate', 'foo'], output: contains('''
Resolving dependencies...
+ bar 1.0.0
+ foo 1.0.0
Downloading'''));
  });

  test('can enable default-off features', () async {
    await servePackages((builder) {
      builder.serve('foo', '1.0.0', pubspec: {
        'features': {
          'stuff': {
            'dependencies': {'bar': '1.0.0'}
          },
          'things': {
            'default': false,
            'dependencies': {'baz': '1.0.0'}
          }
        }
      });

      builder.serve('bar', '1.0.0');
      builder.serve('baz', '1.0.0');
    });

    await runPub(
        args: ['global', 'activate', 'foo', '--features', 'things'],
        output: contains('''
Resolving dependencies...
+ bar 1.0.0
+ baz 1.0.0
+ foo 1.0.0
Downloading'''));
  });

  test('can disable default-on features', () async {
    await servePackages((builder) {
      builder.serve('foo', '1.0.0', pubspec: {
        'features': {
          'stuff': {
            'dependencies': {'bar': '1.0.0'}
          },
          'things': {
            'default': false,
            'dependencies': {'baz': '1.0.0'}
          }
        }
      });

      builder.serve('bar', '1.0.0');
      builder.serve('baz', '1.0.0');
    });

    await runPub(
        args: ['global', 'activate', 'foo', '--omit-features', 'stuff'],
        output: contains('''
Resolving dependencies...
+ foo 1.0.0
Downloading'''));
  });

  test('supports multiple arguments', () async {
    await servePackages((builder) {
      builder.serve('foo', '1.0.0', pubspec: {
        'features': {
          'stuff': {
            'default': false,
            'dependencies': {'bar': '1.0.0'}
          },
          'things': {
            'default': false,
            'dependencies': {'baz': '1.0.0'}
          }
        }
      });

      builder.serve('bar', '1.0.0');
      builder.serve('baz', '1.0.0');
    });

    await runPub(
        args: ['global', 'activate', 'foo', '--features', 'things,stuff'],
        output: contains('''
Resolving dependencies...
+ bar 1.0.0
+ baz 1.0.0
+ foo 1.0.0
Downloading'''));
  });

  test('can both enable and disable', () async {
    await servePackages((builder) {
      builder.serve('foo', '1.0.0', pubspec: {
        'features': {
          'stuff': {
            'dependencies': {'bar': '1.0.0'}
          },
          'things': {
            'default': false,
            'dependencies': {'baz': '1.0.0'}
          }
        }
      });

      builder.serve('bar', '1.0.0');
      builder.serve('baz', '1.0.0');
    });

    await runPub(args: [
      'global',
      'activate',
      'foo',
      '--features',
      'things',
      '--omit-features',
      'stuff'
    ], output: contains('''
Resolving dependencies...
+ baz 1.0.0
+ foo 1.0.0
Downloading'''));
  });
}
