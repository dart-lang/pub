// Copyright (c) 2016, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../descriptor.dart' as d;
import '../test_pub.dart';

main() {
  integration("lists executables in entrypoint's bin", () {
    d.dir(appPath, [
      d.appPubspec(),
      d.dir('bin', [
        d.file('foo.dart'),
        d.file('bar.dart')
      ])
    ]).create();

    schedulePub(args: ['run', '--list'], output: 'myapp: bar, foo');
  });

  integration("doesn't list executables in bin's sub directories", () {
    d.dir(appPath, [
      d.appPubspec(),
      d.dir('bin', [
        d.file('foo.dart'),
        d.dir('sub', [
          d.file('bar.dart')
        ])
      ])
    ]).create();

    schedulePub(args: ['run', '--list'], output: 'myapp:foo');
  });

  integration('lists only Dart files', () {
    d.dir(appPath, [
      d.appPubspec(),
      d.dir('bin', [
        d.file('foo.dart'),
        d.file('bar.sh')
      ])
    ]).create();

    schedulePub(args: ['run', '--list'], output: 'myapp:foo');
  });

  integration('lists executables from a dependency', () {
    d.dir('foo', [
      d.libPubspec('foo', '1.0.0'),
      d.dir('bin', [
        d.file('bar.dart')
      ])
    ]).create();

    d.dir(appPath, [
      d.appPubspec({
        'foo': {'path': '../foo'}
      })
    ]).create();

    pubGet();
    schedulePub(args: ['run', '--list'], output: 'foo:bar');
  });

  integration('lists executables only from immediate dependencies', () {
    d.dir(appPath, [
      d.appPubspec({
        'foo': {'path': '../foo'}
      })
    ]).create();

    d.dir('foo', [
      d.libPubspec('foo', '1.0.0', deps: {
        'baz': {'path': '../baz'}
      }),
      d.dir('bin', [
        d.file('bar.dart')
      ])
    ]).create();

    d.dir('baz', [
      d.libPubspec('baz', '1.0.0'),
      d.dir('bin', [
        d.file('qux.dart')
      ])
    ]).create();


    pubGet();
    schedulePub(args: ['run', '--list'], output: 'foo:bar');
  });

  integration('applies formatting before printing executables', () {
    d.dir(appPath, [
      d.appPubspec({
        'foo': {'path': '../foo'},
        'bar': {'path': '../bar'}
      }),
      d.dir('bin', [
        d.file('myapp.dart')
      ])
    ]).create();

    d.dir('foo', [
      d.libPubspec('foo', '1.0.0'),
      d.dir('bin', [
        d.file('baz.dart'),
        d.file('foo.dart')
      ])
    ]).create();

    d.dir('bar', [
      d.libPubspec('bar', '1.0.0'),
      d.dir('bin', [
        d.file('qux.dart')
      ])
    ]).create();

    pubGet();
    schedulePub(args: ['run', '--list'], output: '''
myapp
bar:qux
foo: foo, baz
''');
  });

  integration('prints blank line when no executables found', () {
    d.dir(appPath, [
      d.appPubspec()
    ]).create();

    schedulePub(args: ['run', '--list'], output: '\n');
  });
}
