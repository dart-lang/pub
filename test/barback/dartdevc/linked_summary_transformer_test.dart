// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/src/summary/idl.dart';
import 'package:scheduled_test/scheduled_test.dart';

import 'package:pub/src/barback/dartdevc/summaries.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';
import '../../serve/utils.dart';

main() {
  integration(
      "can output linked analyzer summaries for modules under lib and web", () {
    d.dir("foo", [
      d.libPubspec("foo", "1.0.0"),
      d.dir("lib", [
        d.file(
            "foo.dart",
            """
  void foo() {}
  """)
      ]),
    ]).create();

    d.dir(appPath, [
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

    pubGet();
    pubServe(args: ['--compiler', 'dartdevc']);

    linkedSummaryRequestShouldSucceed('web__main$linkedSummaryExtension', [
      'file://web/main.dart',
      'package:myapp/hello.dart',
      'package:foo/foo.dart'
    ], [
      'file://web/main.dart'
    ], [
      endsWith('packages/myapp/lib__hello.unlinked.sum'),
      endsWith('packages/foo/lib__foo.unlinked.sum'),
    ]);
    linkedSummaryRequestShouldSucceed(
        'packages/myapp/lib__hello$linkedSummaryExtension', [
      'package:myapp/hello.dart',
      'package:foo/foo.dart'
    ], [
      'package:myapp/hello.dart'
    ], [
      endsWith('packages/foo/lib__foo.unlinked.sum'),
    ]);
    linkedSummaryRequestShouldSucceed(
        'packages/foo/lib__foo$linkedSummaryExtension',
        ['package:foo/foo.dart'],
        ['package:foo/foo.dart']);
    endPubServe();
  });
}

void linkedSummaryRequestShouldSucceed(String uri,
    List<String> expectedLinkedUris, List<String> expectedUnlinkedUris,
    [List<Matcher> expectedSummaryDeps = const []]) {
  scheduleRequest(uri).then((response) {
    expect(response.statusCode, 200);
    var bundle = new PackageBundle.fromBuffer(response.bodyBytes);
    expect(bundle.linkedLibraryUris, unorderedMatches(expectedLinkedUris));
    expect(bundle.unlinkedUnitUris, unorderedMatches(expectedUnlinkedUris));
    var summaryDepPaths = bundle.dependencies
        .map((info) => info.summaryPath)
        .where((path) => path.isNotEmpty);
    expect(summaryDepPaths, unorderedMatches(expectedSummaryDeps));
  });
}
