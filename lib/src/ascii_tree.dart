// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A simple library for rendering tree-like structures in Unicode symbols with
/// a fallback to ASCII.
library;

import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

import 'log.dart' as log;
import 'utils.dart';

/// Draws a tree for the given list of files
///
/// Shows each file with the file size if [showFileSizes] is `true`.
/// This will stats each file in the list for finding the size.
///
/// Given files like:
///
///     TODO
///     example/console_example.dart
///     example/main.dart
///     example/web copy/web_example.dart
///     test/absolute_test.dart
///     test/basename_test.dart
///     test/normalize_test.dart
///     test/relative_test.dart
///     test/split_test.dart
///     .gitignore
///     README.md
///     lib/path.dart
///     pubspec.yaml
///     test/all_test.dart
///     test/path_posix_test.dart
///     test/path_windows_test.dart
///
/// this renders:
///
///     |-- .gitignore (1 KB)
///     |-- README.md (23 KB)
///     |-- TODO (1 MB)
///     |-- example
///     |   |-- console_example.dart (20 B)
///     |   |-- main.dart (200 B)
///     |   '-- web copy
///     |       '-- web_example.dart (3 KB)
///     |-- lib
///     |   '-- path.dart (4 KB)
///     |-- pubspec.yaml (10 KB)
///     '-- test
///         |-- absolute_test.dart (102 KB)
///         |-- all_test.dart (100 KB)
///         |-- basename_test.dart (4 KB)
///         |-- path_windows_test.dart (2 KB)
///         |-- relative_test.dart (10 KB)
///         '-- split_test.dart (50 KB)
///
/// If [baseDir] is passed, it will be used as the root of the tree.

String fromFiles(
  List<String> files, {
  String? baseDir,
  required bool showFileSizes,
}) {
  // Parse out the files into a tree of nested maps.
  final root = <String, Map>{};
  for (var file in files) {
    final relativeFile =
        baseDir == null ? file : p.relative(file, from: baseDir);
    final parts = p.split(relativeFile);
    if (showFileSizes) {
      final stat = File(p.normalize(file)).statSync();
      if (stat.type != FileSystemEntityType.directory) {
        final size = stat.size;
        final sizeString = _readableFileSize(size);
        parts.last = '${parts.last} $sizeString';
      }
    }
    var directory = root;
    for (var part in parts) {
      directory =
          directory.putIfAbsent(part, () => <String, Map>{})
              as Map<String, Map>;
    }
  }

  // Walk the map recursively and render to a string.
  return fromMap(root, startingAtTop: false);
}

/// Draws a tree from a nested map. Given a map like:
///
///     {
///       "analyzer": {
///         "args": {
///           "collection": ""
///         },
///         "logging": {}
///       },
///       "barback": {}
///     }
///
/// this renders:
///
///     analyzer
///     |-- args
///     |   '-- collection
///     '---logging
///     barback
///
/// Items with no children should have an empty map as the value.
///
/// If [startingAtTop] is `false`, the tree will be shown as:
///
///     |-- analyzer
///     |   '-- args
///     |   |   '-- collection
///     '   '---logging
///     '---barback
String fromMap(Map<String, Map> map, {bool startingAtTop = true}) {
  final buffer = StringBuffer();
  _draw(buffer, '', null, map, depth: startingAtTop ? 0 : 1);
  return buffer.toString();
}

void _drawLine(
  StringBuffer buffer,
  String prefix,
  bool isLastChild,
  String? name,
  bool isRoot,
) {
  // Print lines.
  buffer.write(prefix);
  if (!isRoot) {
    if (isLastChild) {
      buffer.write(log.gray(emoji('└── ', "'-- ")));
    } else {
      buffer.write(log.gray(emoji('├── ', '|-- ')));
    }
  }

  // Print name.
  buffer.writeln(name);
}

String _getPrefix(bool isRoot, bool isLast) {
  if (isRoot) return '';
  if (isLast) return '    ';
  return log.gray(emoji('│   ', '|   '));
}

void _draw(
  StringBuffer buffer,
  String prefix,
  String? name,
  Map<String, Map> children, {
  bool showAllChildren = false,
  bool isLast = false,
  required int depth,
}) {
  // Don't draw a line for the root node.
  if (name != null) _drawLine(buffer, prefix, isLast, name, depth <= 1);

  // Recurse to the children.
  final childNames = children.keys.sorted();

  void drawChild(bool isLastChild, String child) {
    final childPrefix = _getPrefix(depth <= 1, isLast);
    _draw(
      buffer,
      '$prefix$childPrefix',
      child,
      children[child] as Map<String, Map>,
      showAllChildren: showAllChildren,
      isLast: isLastChild,
      depth: depth + 1,
    );
  }

  for (var i = 0; i < childNames.length; i++) {
    drawChild(i == childNames.length - 1, childNames[i]);
  }
}

String _readableFileSize(int size) {
  if (size >= 1 << 30) {
    return log.red('(${size ~/ (1 << 30)} GB)');
  } else if (size >= 1 << 20) {
    return log.yellow('(${size ~/ (1 << 20)} MB)');
  } else if (size >= 1 << 10) {
    return log.gray('(${size ~/ (1 << 10)} KB)');
  } else {
    return log.gray('(<1 KB)');
  }
}
