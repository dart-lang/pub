// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

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
  test("can log messages", () async {
    await serveBarback();

    await d.dir(appPath, [
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

    await pubGet();
    var pub = await startPub(args: ["build"]);
    expect(pub.stdout, emits(startsWith("Loading source assets...")));
    expect(pub.stdout, mayEmitMultiple(matches("Loading .* transformers...")));
    expect(pub.stdout, emits(startsWith("Building myapp...")));

    expect(pub.stdout, emitsLines("""
[Rewrite on myapp|web/foo.txt]:
info!"""));

    expect(pub.stderr, emitsLines("""
[Rewrite on myapp|web/foo.txt with input myapp|web/foo.foo]:
Warning!
[Rewrite on myapp|web/foo.txt]:"""));

    // The details of the analyzer's error message change pretty frequently,
    // so instead of validating the entire line, just look for a couple of
    // salient bits of information.
    expect(
        pub.stderr,
        emits(allOf([
          contains("2"), // The line number.
          contains("1"), // The column number.
          contains("http://fake.com/not_real.dart"), // The library.
          contains("ERROR"), // That it's an error.
        ])));

    // In barback >=0.15.0, the span will point to the location where the error
    // occurred.
    expect(pub.stderr, mayEmit(emitsInOrder(["d", "^"])));

    expect(pub.stderr, emits("Build failed."));

    await pub.shouldExit(exit_codes.DATA);
  });
}
