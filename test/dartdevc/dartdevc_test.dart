// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../serve/utils.dart';
import '../test_pub.dart';

main() {
  group("can compile js files for modules under lib and web", () {
    d.DirectoryDescriptor appDir;
    d.DirectoryDescriptor appLibDir;
    d.FileDescriptor appHelloFile;

    setUp(() async {
      await d.dir("foo", [
        d.libPubspec("foo", "1.0.0"),
        d.dir("lib", [
          d.file("foo.dart", """
  String get message => 'hello';
  """)
        ]),
      ]).create();

      appHelloFile = d.file("hello.dart", """
import 'package:foo/foo.dart';

hello() => message;
""");
      appLibDir = d.dir("lib", [appHelloFile]);
      appDir = d.dir(appPath, [
        d.appPubspec({
          "foo": {"path": "../foo"}
        }),
        appLibDir,
        d.dir("web", [
          d.file("main.dart", """
import 'package:myapp/hello.dart';

void main() {
  print(hello());
}
""")
        ])
      ]);
      await appDir.create();

      await pubGet();
      await pubServe(args: ['--web-compiler', 'dartdevc']);
    });

    test("on initial build", () async {
      // Just confirm some basic things are present indicating that the module
      // was compiled. The goal here is not to test dartdevc itself.
      await requestShouldSucceed('web__main.js', contains('main'));
      await requestShouldSucceed('web__main.js.map', contains('web__main.js'));
      await requestShouldSucceed(
          'packages/myapp/lib__hello.js', contains('hello'));
      await requestShouldSucceed(
          'packages/myapp/lib__hello.js.map', contains('lib__hello.js'));
      await requestShouldSucceed(
          'packages/foo/lib__foo.js', contains('message'));
      await requestShouldSucceed(
          'packages/foo/lib__foo.js.map', contains('lib__foo.js'));
      await requestShould404('invalid.js');
      await requestShould404('packages/foo/invalid.js');
      await endPubServe();
    });

    // Creates a world.dart file under lib/src for the main app.
    Future _addWorldDotDart() async {
      var srcDir = d.dir('src', [
        d.file("world.dart", """
  world() => "world";
  """)
      ]);
      await srcDir.create(p.join(d.sandbox, appDir.name, appLibDir.name));
      // TODO(jakemac53): Better solution here, we need to give pub a bit of
      // time to recognize the file change. See below as well.
      await new Future.delayed(new Duration(seconds: 1));
    }

    test("after adding new files", () async {
      // Make sure to force an initial build.
      await requestShouldSucceed('web__main.js', contains('main'));

      // Create a new file at lib/src/world.dart
      await _addWorldDotDart();

      // Request it, it ends up in its own module since it's not imported by
      // any entrypoint.
      await requestShouldSucceed(
          'packages/myapp/lib__src__world.js', contains('world'));
      await requestShouldSucceed('packages/myapp/lib__src__world.js.map',
          contains('lib__src__world.js'));
      await endPubServe();
    });

    test("after file edits that cause module restructuring", () async {
      // Make sure to force an initial build.
      await requestShouldSucceed('web__main.js', contains('main'));

      // Create a new file at lib/src/world.dart
      await _addWorldDotDart();

      // Edit lib/src/hello.dart to import that file.
      var helloFile = new File(
          p.join(d.sandbox, appDir.name, appLibDir.name, appHelloFile.name));
      assert(helloFile.existsSync());
      await helloFile.writeAsString("""
  import "package:foo/foo.dart";
  import "src/world.dart";

  hello() => print(hello() + " " + world());
  """);
      // TODO(jakemac53): Better solution here, we need to give pub a bit of
      // time to recognize the file change. See below as well.
      await new Future.delayed(new Duration(seconds: 1));

      await requestShouldSucceed('packages/myapp/lib__hello.js',
          allOf(contains('hello'), contains('world')));
      await requestShouldSucceed(
          'packages/myapp/lib__hello.js.map', contains('lib__hello.js'));

      // Should not get a module for `world.dart` on its own, it should be
      // folded into the `hello.dart` module.
      await requestShould404('packages/myapp/lib__src__world.js');
      await endPubServe();
    });
  });

  group('basic app', () {
    setUp(() async {
      await d.dir(appPath, [
        d.appPubspec(),
        d.dir("lib", [
          d.file("main.dart", 'void main() {}'),
        ]),
        d.dir("web", [
          d.file("main.dart", 'void main() {}'),
          d.dir("subdir", [
            d.file("main.dart", 'void main() {}'),
          ]),
        ]),
      ]).create();

      await pubGet();
      await pubServe(args: ['--web-compiler', 'dartdevc']);
    });

    test("dartdevc resources are copied next to entrypoints", () async {
      await requestShouldSucceed('dart_sdk.js', null);
      await requestShouldSucceed('require.js', null);
      await requestShouldSucceed('dart_stack_trace_mapper.js', null);
      await requestShouldSucceed('ddc_web_compiler.js', null);
      await requestShould404('dart_sdk.js.map');
      await requestShould404('require.js.map');
      await requestShould404('dart_stack_trace_mapper.js.map');
      await requestShould404('ddc_web_compiler.js.map');
      await requestShouldSucceed('subdir/dart_sdk.js', null);
      await requestShouldSucceed('subdir/require.js', null);
      await requestShouldSucceed('subdir/dart_stack_trace_mapper.js', null);
      await requestShouldSucceed('subdir/ddc_web_compiler.js', null);
      await requestShould404('subdir/dart_sdk.js.map');
      await requestShould404('subdir/require.js.map');
      await requestShould404('subdir/dart_stack_trace_mapper.js.map');
      await requestShould404('subdir/ddc_web_compiler.js.map');
      await endPubServe();
    });

    // Regression test for https://github.com/dart-lang/pub/issues/1638.
    test("can request the bootstrap.js file before the dart.js file", () async {
      await requestShouldSucceed('subdir/main.dart.bootstrap.js', null);
      await requestShouldSucceed('subdir/main.dart.js', null);
      await endPubServe();
    });
  });

  group('custom analysis options', () {
    setUp(() async {
      await d.dir("foo", [
        d.libPubspec("foo", "1.0.0"),
        d.dir("lib", [
          d.file("foo.dart", """
// not actually a used input
import 'dart:io';

String get message => 'hello';
""")
        ]),
      ]).create();

      await d.dir(appPath, [
        d.appPubspec({
          "foo": {"path": "../foo"}
        }),
        d.file("analysis_options.yaml", """
analyzer:
  strong-mode: true
  errors:
    unused_import: error
"""),
        d.dir("web", [
          d.file("main.dart", """
import 'package:foo/foo.dart';

void main() {
  print(message);
}
"""),
          d.file("bad.dart", """
import 'dart:io';

import 'package:foo/foo.dart';

void main() {
  print(message);
}
"""),
        ]),
      ]).create();

      await pubGet();
      await pubServe(args: ['--web-compiler', 'dartdevc']);
    });

    test("the root package can't violate the root analysis options", () async {
      await requestShould404('web__bad.js');
      await endPubServe();
    });

    test("dependencies can violate the root analysis options", () async {
      await requestShouldSucceed('web__main.js', null);
      await endPubServe();
    });
  });
}
