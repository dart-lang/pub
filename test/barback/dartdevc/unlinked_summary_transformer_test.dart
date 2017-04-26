// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/src/summary/idl.dart';
import 'package:scheduled_test/scheduled_test.dart';

import 'package:pub/src/barback/dartdevc/unlinked_summary_transformer.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';
import '../../serve/utils.dart';

main() {
  integration(
      "can output unlinked analyzer summaries for modules under lib and web",
      () {
    d.dir("foo", [
      d.libPubspec("foo", "1.0.0"),
      d.dir("lib", [
        d.file(
            "foo.dart",
            """
  void foo() {};
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

    unlinkedSummaryRequestShouldSucceed(
        'web__main$unlinkedSummaryExtension', ['file://web/main.dart']);
    unlinkedSummaryRequestShouldSucceed(
        'packages/myapp/lib__hello$unlinkedSummaryExtension',
        ['package:myapp/hello.dart']);
    unlinkedSummaryRequestShouldSucceed(
        'packages/foo/lib__foo$unlinkedSummaryExtension',
        ['package:foo/foo.dart']);
    endPubServe();
  });
}

void unlinkedSummaryRequestShouldSucceed(
    String uri, List<String> expectedUnlinkedUris) {
  var expected = unorderedMatches(expectedUnlinkedUris);
  scheduleRequest(uri).then((response) {
    expect(response.statusCode, 200);
    var bundle = new PackageBundle.fromBuffer(response.bodyBytes);
    expect(bundle.unlinkedUnitUris, expected);
  });
}
