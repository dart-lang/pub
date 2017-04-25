// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:pub/src/barback/dartdevc/module.dart';
import 'package:pub/src/barback/dartdevc/module_reader.dart';
import 'package:scheduled_test/scheduled_test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';
import '../../serve/utils.dart';
import 'util.dart';

main() {
  integration("can output modules under lib and web and for deps", () {
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

main() {}
""")
      ])
    ]).create();

    pubGet();
    pubServe(args: ['--compiler', 'dartdevc']);

    moduleRequestShouldSucceed(moduleConfigName, [
      makeModule(
          package: 'myapp',
          name: 'web__main',
          srcs: ['myapp|web/main.dart'],
          directDependencies: ['myapp|lib/hello.dart'])
    ]);
    moduleRequestShouldSucceed('packages/myapp/$moduleConfigName', [
      makeModule(
          package: 'myapp',
          name: 'lib__hello',
          srcs: ['myapp|lib/hello.dart'],
          directDependencies: ['foo|lib/foo.dart'])
    ]);
    moduleRequestShouldSucceed('packages/foo/$moduleConfigName', [
      makeModule(package: 'foo', name: 'lib__foo', srcs: ['foo|lib/foo.dart'])
    ]);

    endPubServe();
  });
}

void moduleRequestShouldSucceed(String uri, List<Module> expectedModules) {
  var expected = unorderedMatches(
      expectedModules.map((module) => equalsModule(module)).toList());
  scheduleRequest(uri).then((response) {
    var json = JSON.decode(response.body);
    var modules =
        json.map((serialized) => new Module.fromJson(serialized)).toList();
    expect(modules, expected);
  });
}
