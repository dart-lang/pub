// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:scheduled_test/scheduled_stream.dart';

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
    var process = startPubServe(args: ['--compiler', 'dartdevc']);
    // TODO(jakemac53): Update when dartdevc is supported.
    process.shouldExit(1);
    process.stderr
        .expect(consumeThrough('The dartdevc compiler is not yet supported.'));
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
          "The `dart2js` arg can't be used with the `compiler` arg. Prefer "
          "using the compiler flag."));
    }
  });
}
