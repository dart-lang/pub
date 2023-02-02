// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('activating a hosted package twice will not precompile', () async {
    final server = await servePackages();
    server
      ..serve(
        'foo',
        '1.0.0',
        deps: {'bar': 'any'},
        contents: [
          d.dir('bin', [
            d.file('foo.dart', r'''
import 'package:bar/bar.dart';
main(args) => print('bar $version');''')
          ])
        ],
      )
      ..serve(
        'bar',
        '1.0.0',
        contents: [
          d.dir('lib', [d.file('bar.dart', 'final version = "1.0.0";')])
        ],
      );

    await runPub(args: ['global', 'activate', 'foo'], output: anything);

    await runPub(
      args: ['global', 'activate', 'foo'],
      output: '''
Package foo is currently active at version 1.0.0.
Resolving dependencies...
The package foo is already activated at newest available version.
To recompile executables, first run `dart pub global deactivate foo`.
Activated foo 1.0.0.''',
    );

    var pub = await pubRun(global: true, args: ['foo']);
    expect(pub.stdout, emits('bar 1.0.0'));
    await pub.shouldExit();

    await runPub(args: ['global', 'activate', 'foo']);

    server.serve(
      'bar',
      '2.0.0',
      contents: [
        d.dir('lib', [d.file('bar.dart', 'final version = "2.0.0";')])
      ],
    );

    await runPub(
      args: ['global', 'activate', 'foo'],
      output: '''
Package foo is currently active at version 1.0.0.
Resolving dependencies...
> bar 2.0.0 (was 1.0.0)
Building package executables...
Built foo:foo.
Activated foo 1.0.0.''',
    );

    var pub2 = await pubRun(global: true, args: ['foo']);
    expect(pub2.stdout, emits('bar 2.0.0'));
    await pub2.shouldExit();
  });
}
