// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:scheduled_test/scheduled_stream.dart';
import 'package:scheduled_test/scheduled_test.dart';

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
      ])
    ]).create();

    pubGet();
    pubServe(args: ['--compiler', 'dartdevc']);
    requestShouldSucceed(
        'packages/$appPath/.moduleConfig', contains('lib__hello'));
    // TODO(jakemac53): Not implemented yet, update once available.
    requestShould404('packages/$appPath/lib__hello.unlinked.sum');
    requestShould404('packages/$appPath/lib__hello.linked.sum');
    requestShould404('packages/$appPath/lib__hello.js');
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
