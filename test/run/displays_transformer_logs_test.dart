// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

const SCRIPT = """
import "package:myapp/lib.dart";
main() {
  callLib();
}
""";

const LIB = """
callLib() {
  print("lib");
}
""";

// Make it lazy so that "lib.dart" isn't transformed until after the process
// is started. Otherwise, since this tranformer modifies .dart files, it will
// be run while the transformers themselves are loading during pub run's
// startup.
const TRANSFORMER = """
import 'dart:async';

import 'package:barback/barback.dart';

class LoggingTransformer extends Transformer implements LazyTransformer {
  LoggingTransformer.asPlugin();

  String get allowedExtensions => '.dart';

  void apply(Transform transform) {
    transform.logger.info('\${transform.primaryInput.id}.');
    transform.logger.warning('\${transform.primaryInput.id}.');
  }

  void declareOutputs(DeclaringTransform transform) {
    // TODO(rnystrom): Remove this when #19408 is fixed.
    transform.declareOutput(transform.primaryId);
  }
}
""";

main() {
  test('displays transformer log messages', () async {
    await serveBarback();

    await d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "transformers": ["myapp/src/transformer"],
        "dependencies": {"barback": "any"}
      }),
      d.dir("lib", [
        d.file("lib.dart", LIB),
        d.dir("src", [d.file("transformer.dart", TRANSFORMER)])
      ]),
      d.dir("bin", [d.file("script.dart", SCRIPT)])
    ]).create();

    await pubGet();
    var pub = await pubRun(args: ["bin/script"]);

    // Note that the info log is only displayed here because the test
    // harness runs pub in verbose mode. By default, only the warning would
    // be shown.
    expect(pub.stdout, emits("[Info from Logging]:"));
    expect(pub.stdout, emits("myapp|bin/script.dart."));

    expect(pub.stderr, emits("[Warning from Logging]:"));
    expect(pub.stderr, emits("myapp|bin/script.dart."));

    expect(pub.stdout, emits("[Info from Logging]:"));
    expect(pub.stdout, emits("myapp|lib/lib.dart."));

    expect(pub.stderr, emits("[Warning from Logging]:"));
    expect(pub.stderr, emits("myapp|lib/lib.dart."));

    expect(pub.stdout, emits("lib"));
    pub.shouldExit();
  });
}
