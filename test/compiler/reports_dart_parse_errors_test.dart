// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Dart2js can take a long time to compile dart code, so we increase the timeout
// to cope with that.
@Timeout.factor(3)
import 'package:path/path.dart' as p;
import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:scheduled_test/scheduled_test.dart';
import 'package:scheduled_test/scheduled_stream.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import '../serve/utils.dart';
import 'utils.dart';

main() {
  setUp(() {
    d.dir(appPath, [
      d.appPubspec(),
      d.dir('web', [
        d.file('file.txt', 'contents'),
        d.file('file.dart', 'void main() {}; void void;'),
        d.dir('subdir', [d.file('subfile.dart', 'void main() {}; void void;')])
      ])
    ]).create();

    pubGet();
  });

  integrationWithCompiler("Pub build reports Dart parse errors", (compiler) {
    var pub = startPub(args: ["build", "--web-compiler", compiler.name]);
    _expectErrors(pub, compiler);

    pub.shouldExit(exit_codes.DATA);

    // Doesn't output anything if an error occurred.
    d.dir(appPath, [
      d.dir('build', [d.nothing('web')])
    ]).validate();
  });

  integrationWithCompiler("Pub serve reports Dart parse errors", (compiler) {
    var pub = pubServe(args: ["--web-compiler", compiler.name]);

    switch (compiler) {
      case Compiler.dartDevc:
        requestShould404('web__file.js');
        requestShouldSucceed(
            'web__file.js.errors',
            allOf(contains('Error compiling dartdevc module'),
                contains('web/file.dart')));
        requestShould404('web__subdir__subfile.js');
        requestShouldSucceed(
            'web__subdir__subfile.js.errors',
            allOf(contains('Error compiling dartdevc module'),
                contains('web/subdir/subfile.dart')));
        break;
      case Compiler.dart2JS:
        requestShould404('file.dart.js');
        requestShould404('subdir/subfile.dart.js');
        break;
    }

    endPubServe();
    _expectErrors(pub, compiler, isBuild: false);
  });
}

void _expectErrors(PubProcess pub, Compiler compiler, {bool isBuild = true}) {
  if (isBuild) {
    pub.stdout.expect(startsWith("Loading source assets..."));
    pub.stdout.expect(startsWith("Building myapp..."));
  }

  var consumeFile;
  var consumeSubfile;
  switch (compiler) {
    case Compiler.dart2JS:
      consumeFile = consumeThrough(inOrder([
        "[Error from Dart2JS]:",
        startsWith(p.join("web", "file.dart") + ":")
      ]));
      consumeSubfile = consumeThrough(inOrder([
        "[Error from Dart2JS]:",
        startsWith(p.join("web", "subdir", "subfile.dart") + ":")
      ]));
      break;
    case Compiler.dartDevc:
      consumeFile = consumeThrough(inOrder([
        startsWith("Error compiling dartdevc module:"),
        anything,
        contains(p.join("web", "file.dart"))
      ]));
      consumeSubfile = consumeThrough(inOrder([
        startsWith("Error compiling dartdevc module:"),
        anything,
        contains(p.join("web", "subdir", "subfile.dart"))
      ]));
      break;
  }

  // It's nondeterministic what order the dart2js transformers start running,
  // so we allow the error messages to be emitted in either order.
  pub.stderr.expect(either(inOrder([consumeFile, consumeSubfile]),
      inOrder([consumeSubfile, consumeFile])));
}
