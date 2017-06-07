// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:analyzer/src/summary/idl.dart';
import 'package:test/test.dart';

import 'package:pub/src/dartdevc/summaries.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import '../serve/utils.dart';

main() {
  test("can output linked analyzer summaries for modules under lib and web",
      () async {
    await d.dir("foo", [
      d.libPubspec("foo", "1.0.0"),
      d.dir("lib", [
        d.file(
            "foo.dart",
            """
  void foo() {}
  """)
      ]),
    ]).create();

    await d.dir(appPath, [
      d.appPubspec({
        "foo": {"path": "../foo"}
      }),
      d.dir("lib", [
        d.file(
            "hello.dart",
            """
import 'package:foo/foo.dart';

hello() => 'hello';
""")
      ]),
      d.dir("web", [
        d.file(
            "main.dart",
            """
import 'package:myapp/hello.dart';

void main() {}
""")
      ])
    ]).create();

    await pubGet();
    await pubServe(args: ['--web-compiler', 'dartdevc']);

    await linkedSummaryRequestShouldSucceed(
        'web__main$linkedSummaryExtension', [
      endsWith('web/main.dart'),
      equals('package:myapp/hello.dart'),
      equals('package:foo/foo.dart')
    ], [
      endsWith('web/main.dart')
    ], [
      endsWith('packages/myapp/lib__hello.unlinked.sum'),
      endsWith('packages/foo/lib__foo.unlinked.sum'),
    ]);
    await linkedSummaryRequestShouldSucceed(
        'packages/myapp/lib__hello$linkedSummaryExtension', [
      equals('package:myapp/hello.dart'),
      equals('package:foo/foo.dart')
    ], [
      equals('package:myapp/hello.dart')
    ], [
      endsWith('packages/foo/lib__foo.unlinked.sum'),
    ]);
    await linkedSummaryRequestShouldSucceed(
        'packages/foo/lib__foo$linkedSummaryExtension',
        [equals('package:foo/foo.dart')],
        [equals('package:foo/foo.dart')]);
    await requestShould404('invalid$linkedSummaryExtension');
    await requestShould404('packages/foo/invalid$linkedSummaryExtension');
    await endPubServe();
  });

  test("can output unlinked analyzer summaries for modules under lib and web",
      () async {
    await d.dir("foo", [
      d.libPubspec("foo", "1.0.0"),
      d.dir("lib", [
        d.file(
            "foo.dart",
            """
    void foo() {}
    """)
      ]),
    ]).create();

    await d.dir(appPath, [
      d.appPubspec({
        "foo": {"path": "../foo"}
      }),
      d.dir("lib", [
        d.file(
            "hello.dart",
            """
  import 'package:foo/foo.dart';

  hello() => 'hello';
  """)
      ]),
      d.dir("web", [
        d.file(
            "main.dart",
            """
  import 'package:myapp/hello.dart';

  void main() {}
  """)
      ])
    ]).create();

    await pubGet();
    await pubServe(args: ['--web-compiler', 'dartdevc']);

    await unlinkedSummaryRequestShouldSucceed(
        'web__main$unlinkedSummaryExtension', [endsWith('web/main.dart')]);
    await unlinkedSummaryRequestShouldSucceed(
        'packages/myapp/lib__hello$unlinkedSummaryExtension',
        [equals('package:myapp/hello.dart')]);
    await unlinkedSummaryRequestShouldSucceed(
        'packages/foo/lib__foo$unlinkedSummaryExtension',
        [equals('package:foo/foo.dart')]);
    await requestShould404('invalid$unlinkedSummaryExtension');
    await requestShould404('packages/foo/invalid$unlinkedSummaryExtension');
    await endPubServe();
  });
}

Future linkedSummaryRequestShouldSucceed(String uri,
    List<Matcher> expectedLinkedUris, List<Matcher> expectedUnlinkedUris,
    [List<Matcher> expectedSummaryDeps = const []]) async {
  var response = await requestFromPub(uri);
  expect(response.statusCode, 200);
  var bundle = new PackageBundle.fromBuffer(response.bodyBytes);
  expect(bundle.linkedLibraryUris, unorderedMatches(expectedLinkedUris));
  expect(bundle.unlinkedUnitUris, unorderedMatches(expectedUnlinkedUris));
  var summaryDepPaths = bundle.dependencies
      .map((info) => info.summaryPath)
      .where((path) => path.isNotEmpty);
  expect(summaryDepPaths, unorderedMatches(expectedSummaryDeps));
}

Future unlinkedSummaryRequestShouldSucceed(
    String uri, List<Matcher> expectedUnlinkedUris) async {
  var expected = unorderedMatches(expectedUnlinkedUris);
  var response = await requestFromPub(uri);
  expect(response.statusCode, 200);
  var bundle = new PackageBundle.fromBuffer(response.bodyBytes);
  expect(bundle.unlinkedUnitUris, expected);
}
