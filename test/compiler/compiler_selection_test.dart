// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/dartdevc/module_reader.dart';
import 'package:pub/src/exit_codes.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import '../serve/utils.dart';
import 'utils.dart';

main() {
  testWithCompiler("--web-compiler option switches compilers",
      (compiler) async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir("lib", [
        d.file("hello.dart", "hello() => print('hello');"),
      ]),
      d.dir("web", [
        d.file(
            "main.dart",
            '''
          import 'package:myapp/hello.dart';

          void main() => hello();
        '''),
      ]),
    ]).create();

    await pubGet();
    await pubServe(compiler: compiler);
    switch (compiler) {
      case Compiler.dartDevc:
        await requestShouldSucceed(
            'packages/$appPath/$moduleConfigName', contains('lib__hello'));
        await requestShouldSucceed(moduleConfigName, contains('web__main'));
        await requestShouldSucceed(
            'packages/$appPath/lib__hello.unlinked.sum', null);
        await requestShouldSucceed('web__main.unlinked.sum', null);
        await requestShouldSucceed(
            'packages/$appPath/lib__hello.linked.sum', null);
        await requestShouldSucceed('web__main.linked.sum', null);
        await requestShouldSucceed(
            'packages/$appPath/lib__hello.js', contains('hello'));
        await requestShouldSucceed(
            'packages/$appPath/lib__hello.js.map', contains('lib__hello.js'));
        await requestShouldSucceed('web__main.js', contains('hello'));
        await requestShouldSucceed(
            'web__main.js.map', contains('web__main.js'));
        await requestShouldSucceed('dart_sdk.js', null);
        await requestShouldSucceed('require.js', null);
        await requestShouldSucceed('main.dart.js', null);
        break;
      case Compiler.dart2JS:
        await requestShouldSucceed('main.dart.js', null);
        await requestShould404('web__main.js');
        break;
      case Compiler.none:
        await requestShould404('main.dart.js');
        break;
    }
    await endPubServe();
  }, compilers: Compiler.all);

  test("invalid --web-compiler option gives an error", () async {
    await d.dir(appPath, [
      d.appPubspec(),
    ]).create();

    await pubGet();
    var process = await startPubServe(args: ['--web-compiler', 'invalid']);
    await process.shouldExit(USAGE);
    expect(
        process.stderr,
        emitsThrough(
            '"invalid" is not an allowed value for option "web-compiler".'));
  });

  test("--dart2js with --web-compiler is invalid", () async {
    await d.dir(appPath, [
      d.appPubspec(),
    ]).create();

    await pubGet();
    var argCombos = [
      ['--dart2js', '--web-compiler=dartdevc'],
      ['--no-dart2js', '--web-compiler=dartdevc'],
      ['--dart2js', '--web-compiler=dart2js'],
      ['--no-dart2js', '--web-compiler=dart2js'],
    ];
    for (var args in argCombos) {
      var process = await startPubServe(args: args);
      await process.shouldExit(USAGE);
      expect(
          process.stderr,
          emitsThrough(
              "The --dart2js flag can't be used with the --web-compiler arg. Prefer "
              "using the --web-compiler arg as --[no]-dart2js is deprecated."));
    }
  });

  testWithCompiler("web compiler can be set in the pubspec", (compiler) async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'web': {
          'compiler': {'debug': compiler.name}
        },
      }),
      d.dir('web', [
        d.file(
            'main.dart',
            '''
          void main() => print('hello');
        '''),
      ]),
    ]).create();

    await pubGet();
    await pubServe(args: ['--mode', 'debug']);
    switch (compiler) {
      case Compiler.dartDevc:
        await requestShouldSucceed(moduleConfigName, contains('web__main'));
        await requestShouldSucceed('web__main.js', contains('hello'));
        break;
      case Compiler.dart2JS:
        await requestShouldSucceed('main.dart.js', contains('hello'));
        await requestShould404('web__main.js');
        break;
    }
    await endPubServe();
  });

  testWithCompiler("--web-compiler flag overrides pubspec config",
      (compiler) async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'web': {
          'compiler': {'debug': Compiler.none.name}
        },
      }),
      d.dir('web', [
        d.file(
            'main.dart',
            '''
          void main() => print('hello');
        '''),
      ]),
    ]).create();

    await pubGet();
    await pubServe(compiler: compiler, args: ['--mode', 'debug']);
    switch (compiler) {
      case Compiler.dartDevc:
        await requestShouldSucceed(moduleConfigName, contains('web__main'));
        await requestShouldSucceed('web__main.js', contains('hello'));
        break;
      case Compiler.dart2JS:
        await requestShouldSucceed('main.dart.js', contains('hello'));
        await requestShould404('web__main.js');
        break;
    }
    await endPubServe();
  });
}
