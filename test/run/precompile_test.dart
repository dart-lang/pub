// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'package:pub/src/path.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

const _script = r'''
import 'dart:io';

main(List<String> args) {
  print('running with PUB_CACHE: "${Platform.environment['PUB_CACHE']}"');
}
''';

void main() {
  test('`get --precompile` warns and does nothing', () async {
    await d.dir(appPath, [
      d.appPubspec(dependencies: {'test': '1.0.0'}),
    ]).create();

    final server = await servePackages();
    server.serve(
      'test',
      '1.0.0',
      contents: [
        d.dir('bin', [d.file('test.dart', _script)]),
      ],
    );

    await pubGet(
      args: ['--precompile'],
      warning: contains(
        'The --precompile flag is no longer used and does nothing.',
      ),
      output: isNot(contains('Building package executables...')),
    );

    await d.nothing(p.join(appPath, '.dart_tool', 'pub', 'bin')).validate();
  });

  // Regression test of https://github.com/dart-lang/pub/issues/2483
  test('`pub run` runs script with relative PUB_CACHE', () async {
    await d.dir(appPath, [
      d.appPubspec(dependencies: {'test': '1.0.0'}),
    ]).create();

    final server = await servePackages();
    server.serve(
      'test',
      '1.0.0',
      contents: [
        d.dir('bin', [d.file('test.dart', _script)]),
      ],
    );

    await pubGet(environment: {'PUB_CACHE': '.pub_cache'});

    final pub = await pubRun(
      args: ['test'],
      environment: {'PUB_CACHE': '.pub_cache'},
    );
    await pub.shouldExit(0);
    final lines = await pub.stdout.rest.toList();
    expect(lines, contains('running with PUB_CACHE: ".pub_cache"'));
  });
}
