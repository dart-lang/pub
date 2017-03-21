// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Dart2js can take a long time to compile dart code, so we increase the timeout
// to cope with that.
@Timeout.factor(3)
import 'package:scheduled_test/scheduled_test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

main() {
  setUp(() {
    d.dir(appPath, [
      d.appPubspec(),
      d.dir('benchmark', [
        d.file('file.dart', 'void main() => print("hello");'),
        d.file('lib.dart', 'void foo() => print("hello");'),
        d.dir(
            'subdir', [d.file('subfile.dart', 'void main() => print("ping");')])
      ]),
      d.dir('foo', [
        d.file('file.dart', 'void main() => print("hello");'),
        d.file('lib.dart', 'void foo() => print("hello");'),
        d.dir(
            'subdir', [d.file('subfile.dart', 'void main() => print("ping");')])
      ]),
      d.dir('web', [
        d.file('file.dart', 'void main() => print("hello");'),
        d.file('lib.dart', 'void foo() => print("hello");'),
        d.dir(
            'subdir', [d.file('subfile.dart', 'void main() => print("ping");')])
      ])
    ]).create();

    pubGet();
  });

  integration("dart2js compiles Dart entrypoints in root package to JS", () {
    schedulePub(
        args: ["build", "benchmark", "foo", "web"],
        output: new RegExp(r'Built 6 files to "build".'));
    validateBuild();
  });

  integration("dartdevc compiles Dart entrypoints in root package to JS", () {
    schedulePub(
        args: ["build", "benchmark", "foo", "web", "--compiler=dartdevc"],
        output: new RegExp(r'Built \d* files to "build".'));
    validateBuild();
  });
}

void validateBuild() {
  d.dir(appPath, [
    d.dir('build', [
      d.dir('benchmark', [
        d.matcherFile('file.dart.js', isNot(isEmpty)),
        d.nothing('file.dart'),
        d.nothing('lib.dart'),
        d.dir('subdir', [
          d.matcherFile('subfile.dart.js', isNot(isEmpty)),
          d.nothing('subfile.dart')
        ])
      ]),
      d.dir('foo', [
        d.matcherFile('file.dart.js', isNot(isEmpty)),
        d.nothing('file.dart'),
        d.nothing('lib.dart'),
        d.dir('subdir', [
          d.matcherFile('subfile.dart.js', isNot(isEmpty)),
          d.nothing('subfile.dart')
        ])
      ]),
      d.dir('web', [
        d.matcherFile('file.dart.js', isNot(isEmpty)),
        d.nothing('file.dart'),
        d.nothing('lib.dart'),
        d.dir('subdir', [
          d.matcherFile('subfile.dart.js', isNot(isEmpty)),
          d.nothing('subfile.dart')
        ])
      ])
    ])
  ]).validate();
}
