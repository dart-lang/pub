// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/ascii_tree.dart' as tree;
import 'package:pub/src/package.dart';
import 'package:test/test.dart';

import 'descriptor.dart';
import 'test_pub.dart';

/// Removes ansi color codes from [s].
String stripColors(String s) {
  return s.replaceAll(RegExp('\u001b\\[.*?m'), '');
}

void main() {
  group('tree.fromFiles', () {
    test('no files', () {
      expect(stripColors(tree.fromFiles([])), equals(''));
    });

    List<int> bytes(int size) => List.filled(size, 0);
    test('a complex example', () async {
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
      expect(stripColors(tree.fromFiles(files, baseDir: sandbox)), equals('''
'-- myapp
    |-- README.md (100 B)
    |-- TODO (10 B)
    |-- example
    |   |-- console_example.dart (1000 B)
    |   |-- main.dart (1 KB)
    |   '-- web copy
    |       '-- web_example.dart (1 KB)
    |-- lib
    |   '-- path.dart (100 B)
    |-- pubspec.yaml (144 B)
    '-- test
        |-- absolute_test.dart (0 B)
        |-- all_test.dart (100 B)
        |-- basename_test.dart (1 MB)
        |-- dirname_test.dart (1 MB)
        |-- extension_test.dart (2 KB)
        |-- is_absolute_test.dart (2 KB)
        |-- is_relative_test.dart (25 MB)
        |-- join_test.dart (1023 B)
        |-- normalize_test.dart (1023 KB)
        |-- path_posix_test.dart (100 B)
        |-- path_windows_test.dart (100 B)
        |-- relative_test.dart (100 B)
        '-- split_test.dart (1 B)
'''));
    });
  });

  group('treeFromMap', () {
    test('empty map', () {
      expect(stripColors(tree.fromMap({})), equals(''));
    });

    test('a complex example', () {
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

      expect(stripColors(tree.fromMap(map)), equals("""
|-- .gitignore
|-- README.md
|-- TODO
|-- example
|   |-- console_example.dart
|   |-- main.dart
|   '-- web copy
|       '-- web_example.dart
|-- lib
|   '-- path.dart
|-- pubspec.yaml
'-- test
    |-- absolute_test.dart
    |-- basename_test.dart
    |-- dirname_test.dart
    |-- extension_test.dart
    |-- is_absolute_test.dart
    |-- is_relative_test.dart
    |-- join_test.dart
    |-- normalize_test.dart
    |-- relative_test.dart
    '-- split_test.dart
"""));
    });
  });
}
