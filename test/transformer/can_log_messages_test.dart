// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:scheduled_test/scheduled_test.dart';
import 'package:scheduled_test/scheduled_stream.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

const TRANSFORMER = """
import 'dart:async';

import 'package:barback/barback.dart';
import 'package:source_span/source_span.dart';

class RewriteTransformer extends Transformer {
  RewriteTransformer.asPlugin();

  String get allowedExtensions => '.txt';

  Future apply(Transform transform) {
    transform.logger.info('info!');
    transform.logger.warning('Warning!',
        asset: transform.primaryInput.id.changeExtension('.foo'));
    var sourceFile = new SourceFile('not a real\\ndart file',
        url: 'http://fake.com/not_real.dart');
    transform.logger.error('ERROR!', span: sourceFile.span(11, 12));
    return transform.primaryInput.readAsString().then((contents) {
      var id = transform.primaryInput.id.changeExtension(".out");
      transform.addOutput(new Asset.fromString(id, "\$contents.out"));
    });
  }
}
""";

main() {
  integration("can log messages", () {
    serveBarback();

    d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "transformers": ["myapp/src/transformer"],
        "dependencies": {"barback": "any"}
      }),
      d.dir("lib", [
        d.dir("src", [d.file("transformer.dart", TRANSFORMER)])
      ]),
      d.dir("web", [d.file("foo.txt", "foo")])
    ]).create();

    pubGet();
    var pub = startPub(args: ["build"]);
    pub.stdout.expect(startsWith("Loading source assets..."));
    pub.stdout.expect(consumeWhile(matches("Loading .* transformers...")));
    pub.stdout.expect(startsWith("Building myapp..."));

    pub.stdout.expect(emitsLines("""
[Rewrite on myapp|web/foo.txt]:
info!"""));

    pub.stderr.expect(emitsLines("""
[Rewrite on myapp|web/foo.txt with input myapp|web/foo.foo]:
Warning!
[Rewrite on myapp|web/foo.txt]:"""));

    // The details of the analyzer's error message change pretty frequently,
    // so instead of validating the entire line, just look for a couple of
    // salient bits of information.
    pub.stderr.expect(allOf([
      contains("2"), // The line number.
      contains("1"), // The column number.
      contains("http://fake.com/not_real.dart"), // The library.
      contains("ERROR"), // That it's an error.
    ]));

    // In barback >=0.15.0, the span will point to the location where the error
    // occurred.
    pub.stderr.expect(allow(inOrder(["d", "^"])));

    pub.stderr.expect("Build failed.");

    pub.shouldExit(exit_codes.DATA);
  });
}
