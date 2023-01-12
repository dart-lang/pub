// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/ascii_tree.dart' as tree;
import 'package:pub/src/package.dart';
import 'package:pub/src/utils.dart';
import 'package:test/test.dart';

import 'descriptor.dart';
import 'golden_file.dart';
import 'test_pub.dart';

/// Removes ansi color codes from [s].
String stripColors(String s) {
  return s.replaceAll(RegExp('\u001b\\[.*?m'), '');
}

void main() {
  setUp(() {
    forceColors = ForceColorOption.always;
  });

  tearDown(() {
    forceColors = ForceColorOption.auto;
  });
  test('tree.fromFiles no files', () {
    expect(tree.fromFiles([], showFileSizes: true), equals(''));
  });

  List<int> bytes(int size) => List.filled(size, 0);
  testWithGolden('tree.fromFiles a complex example', colors: true, (ctx) async {
    await dir(appPath, [
      libPubspec('app', '1.0.0'),
      file('TODO', bytes(10)),
      dir('example', [
        file('console_example.dart', bytes(1000)),
        file('main.dart', bytes(1024)),
        dir('web copy', [
          file('web_example.dart', bytes(1025)),
        ]),
      ]),
      dir('test', [
        file('absolute_test.dart', bytes(0)),
        file('basename_test.dart', bytes(1 << 20)),
        file('dirname_test.dart', bytes((1 << 20) + 1)),
        file('extension_test.dart', bytes(2300)),
        file('is_absolute_test.dart', bytes(2400)),
        file('is_relative_test.dart', bytes((1 << 20) * 25)),
        file('join_test.dart', bytes(1023)),
        file('normalize_test.dart', bytes((1 << 20) - 1)),
        file('relative_test.dart', bytes(100)),
        file('split_test.dart', bytes(1)),
        file('all_test.dart', bytes(100)),
        file('path_posix_test.dart', bytes(100)),
        file('path_windows_test.dart', bytes(100)),
      ]),
      file('.gitignore', bytes(100)),
      file('README.md', bytes(100)),
      dir('lib', [
        file('path.dart', bytes(100)),
      ]),
    ]).create();
    var files = Package.load(
      null,
      path(appPath),
      (name) => throw UnimplementedError(),
    ).listFiles();
    ctx.expectNextSection(
      tree.fromFiles(files, baseDir: path(appPath), showFileSizes: true),
    );
  });
  test('tree.fromMap empty map', () {
    expect(tree.fromMap({}), equals(''));
  });

  testWithGolden('tree.fromMap a complex example', colors: true, (ctx) {
    var map = {
      '.gitignore': <String, Map>{},
      'README.md': <String, Map>{},
      'TODO': <String, Map>{},
      'example': {
        'console_example.dart': <String, Map>{},
        'main.dart': <String, Map>{},
        'web copy': {'web_example.dart': <String, Map>{}},
      },
      'lib': {'path.dart': <String, Map>{}},
      'pubspec.yaml': <String, Map>{},
      'test': {
        'absolute_test.dart': <String, Map>{},
        'basename_test.dart': <String, Map>{},
        'dirname_test.dart': <String, Map>{},
        'extension_test.dart': <String, Map>{},
        'is_absolute_test.dart': <String, Map>{},
        'is_relative_test.dart': <String, Map>{},
        'join_test.dart': <String, Map>{},
        'normalize_test.dart': <String, Map>{},
        'relative_test.dart': <String, Map>{},
        'split_test.dart': <String, Map>{}
      }
    };

    ctx.expectNextSection(tree.fromMap(map));
  });
}
