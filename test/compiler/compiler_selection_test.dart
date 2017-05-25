// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:scheduled_test/scheduled_stream.dart';
import 'package:scheduled_test/scheduled_test.dart';

import 'package:pub/src/dartdevc/module_reader.dart';
import 'package:pub/src/exit_codes.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import '../serve/utils.dart';
import 'utils.dart';

main() {
  integrationWithCompiler("js flag switches compilers", (compiler) {
    d.dir(appPath, [
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

    pubGet();
    pubServe(compiler: compiler);
    switch (compiler) {
      case Compiler.dartDevc:
        requestShouldSucceed(
            'packages/$appPath/$moduleConfigName', contains('lib__hello'));
        requestShouldSucceed(moduleConfigName, contains('web__main'));
        requestShouldSucceed('packages/$appPath/lib__hello.unlinked.sum', null);
        requestShouldSucceed('web__main.unlinked.sum', null);
        requestShouldSucceed('packages/$appPath/lib__hello.linked.sum', null);
        requestShouldSucceed('web__main.linked.sum', null);
        requestShouldSucceed(
            'packages/$appPath/lib__hello.js', contains('hello'));
        requestShouldSucceed(
            'packages/$appPath/lib__hello.js.map', contains('lib__hello.js'));
        requestShouldSucceed('web__main.js', contains('hello'));
        requestShouldSucceed('web__main.js.map', contains('web__main.js'));
        requestShouldSucceed('dart_sdk.js', null);
        requestShouldSucceed('require.js', null);
        requestShouldSucceed('main.dart.js', null);
        break;
      case Compiler.dart2JS:
        requestShouldSucceed('main.dart.js', null);
        requestShould404('web__main.js');
        break;
      case Compiler.none:
        requestShould404('main.dart.js');
        break;
    }
    endPubServe();
  }, compilers: Compiler.all);

  integration("invalid js flag gives an error", () {
    d.dir(appPath, [
      d.appPubspec(),
    ]).create();

    pubGet();
    var process = startPubServe(args: ['--js', 'invalid']);
    process.shouldExit(USAGE);
    process.stderr.expect(
        consumeThrough('"invalid" is not an allowed value for option "js".'));
  });

  integration("--dart2js with --js is invalid", () {
    d.dir(appPath, [
      d.appPubspec(),
    ]).create();

    pubGet();
    var argCombos = [
      ['--dart2js', '--js=dartdevc'],
      ['--no-dart2js', '--js=dartdevc'],
      ['--dart2js', '--js=dart2js'],
      ['--no-dart2js', '--js=dart2js'],
    ];
    for (var args in argCombos) {
      var process = startPubServe(args: args);
      process.shouldExit(USAGE);
      process.stderr.expect(consumeThrough(
          "The --dart2js flag can't be used with the --js arg. Prefer "
          "using the --js arg as --[no]-dart2js is deprecated."));
    }
  });

  integrationWithCompiler("js_compiler can be set in the pubspec", (compiler) {
    d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'js_compiler': {'debug': compiler.name}
      }),
      d.dir('web', [
        d.file(
            'main.dart',
            '''
          void main() => print('hello');
        '''),
      ]),
    ]).create();

    pubGet();
    pubServe(args: ['--mode', 'debug']);
    switch (compiler) {
      case Compiler.dartDevc:
        requestShouldSucceed(moduleConfigName, contains('web__main'));
        requestShouldSucceed('web__main.js', contains('hello'));
        break;
      case Compiler.dart2JS:
        requestShouldSucceed('main.dart.js', contains('hello'));
        requestShould404('web__main.js');
        break;
    }
    endPubServe();
  });

  integrationWithCompiler("--js flag overrides pubspec js_compiler config",
      (compiler) {
    d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'js_compiler': {'debug': Compiler.none.name}
      }),
      d.dir('web', [
        d.file(
            'main.dart',
            '''
          void main() => print('hello');
        '''),
      ]),
    ]).create();

    pubGet();
    pubServe(compiler: compiler, args: ['--mode', 'debug']);
    switch (compiler) {
      case Compiler.dartDevc:
        requestShouldSucceed(moduleConfigName, contains('web__main'));
        requestShouldSucceed('web__main.js', contains('hello'));
        break;
      case Compiler.dart2JS:
        requestShouldSucceed('main.dart.js', contains('hello'));
        requestShould404('web__main.js');
        break;
    }
    endPubServe();
  });
}
