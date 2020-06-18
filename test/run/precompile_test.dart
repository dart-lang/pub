// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

const SCRIPT = r'''
import 'dart:io';

main(List<String> args) {
  print('running with PUB_CACHE: "${Platform.environment['PUB_CACHE']}"');
}
''';

void main() {
  Future<void> setupForPubRunToPrecompile() async {
    await d.dir(appPath, [
      d.appPubspec({'test': '1.0.0'}),
    ]).create();

    await servePackages((server) => server
      ..serve('test', '1.0.0', contents: [
        d.dir('bin',
            [d.file('test.dart', 'main(List<String> args) => print("hello");')])
      ]));

    await pubGet(args: ['--no-precompile']);
  }

  test('`pub run` precompiles script', () async {
    await setupForPubRunToPrecompile();
    var pub = await pubRun(args: ['test']);
    await pub.shouldExit(0);
    final lines = await pub.stdout.rest.toList();
    expect(lines, contains('Precompiling executable...'));
    expect(lines, contains('hello'));
  });

  test(
      "`pub run` doesn't write about precompilation when a terminal is not attached",
      () async {
    await setupForPubRunToPrecompile();

    var pub = await pubRun(args: ['test'], verbose: false);
    await pub.shouldExit(0);
    final lines = await pub.stdout.rest.toList();
    expect(lines, isNot(contains('Precompiling executable...')));
    expect(lines, contains('hello'));
  });

  // Regression test of https://github.com/dart-lang/pub/issues/2483
  test('`pub run` precompiles script with relative PUB_CACHE', () async {
    await d.dir(appPath, [
      d.appPubspec({'test': '1.0.0'}),
    ]).create();

    await servePackages((server) => server
      ..serve('test', '1.0.0', contents: [
        d.dir('bin', [d.file('test.dart', SCRIPT)])
      ]));

    await pubGet(
        args: ['--no-precompile'], environment: {'PUB_CACHE': '.pub_cache'});

    var pub = await pubRun(
      args: ['test'],
      environment: {'PUB_CACHE': '.pub_cache'},
    );
    await pub.shouldExit(0);
    final lines = await pub.stdout.rest.toList();
    expect(lines, contains('Precompiling executable...'));
    expect(lines, contains('running with PUB_CACHE: ".pub_cache"'));
  });

  test('`get --precompile` precompiles script', () async {
    await d.dir(appPath, [
      d.appPubspec({'test': '1.0.0'}),
    ]).create();

    await servePackages((server) => server
      ..serve('test', '1.0.0', contents: [
        d.dir('bin', [d.file('test.dart', SCRIPT)])
      ]));

    await pubGet(
        args: ['--precompile'],
        output: contains('Precompiling executables...'));

    var pub = await pubRun(
      args: ['test'],
    );
    await pub.shouldExit(0);
    final lines = await pub.stdout.rest.toList();
    expect(lines, isNot(contains('Precompiling executable...')));
  });

  // Regression test of https://github.com/dart-lang/pub/issues/2483
  test('`get --precompile` precompiles script with relative PUB_CACHE',
      () async {
    await d.dir(appPath, [
      d.appPubspec({'test': '1.0.0'}),
    ]).create();

    await servePackages((server) => server
      ..serve('test', '1.0.0', contents: [
        d.dir('bin', [d.file('test.dart', SCRIPT)])
      ]));

    await pubGet(
        args: ['--precompile'],
        environment: {'PUB_CACHE': '.pub_cache'},
        output: contains('Precompiling executables...'));

    var pub = await pubRun(
      args: ['test'],
      environment: {'PUB_CACHE': '.pub_cache'},
    );
    await pub.shouldExit(0);
    final lines = await pub.stdout.rest.toList();
    expect(lines, isNot(contains('Precompiling executable...')));
    expect(lines, contains('running with PUB_CACHE: ".pub_cache"'));
  });
}
