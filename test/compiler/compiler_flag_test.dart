// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:scheduled_test/scheduled_stream.dart';
import 'package:scheduled_test/scheduled_test.dart';

import 'package:pub/src/barback/dartdevc/module_reader.dart';
import 'package:pub/src/exit_codes.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import '../serve/utils.dart';

main() {
  integration("compiler flag switches compilers", () {
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
    pubServe(args: ['--compiler', 'dartdevc']);
    requestShouldSucceed(
        'packages/$appPath/$moduleConfigName', contains('lib__hello'));
    requestShouldSucceed(moduleConfigName, contains('web__main'));
    requestShouldSucceed('packages/$appPath/lib__hello.unlinked.sum', null);
    requestShouldSucceed('web__main.unlinked.sum', null);
    requestShouldSucceed('packages/$appPath/lib__hello.linked.sum', null);
    requestShouldSucceed('web__main.linked.sum', null);
    requestShouldSucceed('packages/$appPath/lib__hello.js', contains('hello'));
    requestShouldSucceed('web__main.js', contains('hello'));
    // TODO(jakemac53): Not implemented yet, update once available.
    requestShould404('main.dart.js');
    endPubServe();
  });

  integration("invalid compiler flag gives an error", () {
    d.dir(appPath, [
      d.appPubspec(),
    ]).create();

    pubGet();
    var process = startPubServe(args: ['--compiler', 'invalid']);
    process.shouldExit(USAGE);
    process.stderr.expect(consumeThrough(
        '"invalid" is not an allowed value for option "compiler".'));
  });

  integration("--dart2js with --compiler is invalid", () {
    d.dir(appPath, [
      d.appPubspec(),
    ]).create();

    pubGet();
    var argCombos = [
      ['--dart2js', '--compiler=dartdevc'],
      ['--no-dart2js', '--compiler=dartdevc'],
      ['--dart2js', '--compiler=dart2js'],
      ['--no-dart2js', '--compiler=dart2js'],
    ];
    for (var args in argCombos) {
      var process = startPubServe(args: args);
      process.shouldExit(USAGE);
      process.stderr.expect(consumeThrough(
          "The --dart2js flag can't be used with the --compiler arg. Prefer "
          "using the --compiler arg as --[no]-dart2js is deprecated."));
    }
  });
}
