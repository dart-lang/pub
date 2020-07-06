// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:collection' show UnmodifiableListView;

import 'package:meta/meta.dart';
import 'package:yaml/yaml.dart';

import 'equality.dart';
import 'errors.dart';
import 'list_mutations.dart';
import 'map_mutations.dart';
import 'source_edit.dart';
import 'strings.dart';
import 'utils.dart';
import 'wrap.dart';

/// An interface for modififying [YAML][1] documents while preserving comments and
/// whitespaces.
///
/// YAML parsing is supported by `package:yaml`, and modifications are performed as
/// string operations. Each time a modification takes place via one of the public
/// methods, we calculate the expected final result, and parse the result YAML string,
/// and ensure the two YAML trees match, throwing an [AssertionError] otherwise. Such a situation
/// should be extremely rare, and should only occur with degenerate formatting.
///
/// Most modification methods require the user to pass in an Iterable<Object> path that
/// holds the keys/indices to navigate to the element.
///
/// For example,
///
/// ```yaml
/// a: 1
/// b: 2
/// c:
///   - 3
///   - 4
///   - {e: 5, f: [6, 7]}
/// ```
///
/// To get to `7`, our path will be `['c', 2, 'f', 1]`. The path for the base object is the
/// empty array `[]`. All modification methods will throw an [Error] if the path
/// provided is invalid. Note also that that the order of elements in the path is important,
/// and it should be arranged in order of calling, with the first element being the first
/// key or index to be called.
///
/// To dump the YAML after all the modifications have been completed, simply call [toString()].
///
/// [1]: https://yaml.org/
@sealed
class YamlEditor {
  /// List of [SourceEdit]s that have been applied to [_yaml] since the creation of this
  /// instance, in chronological order. Intended to be compatible with `package:analysis_server`.
  final List<SourceEdit> _edits = [];

  UnmodifiableListView<SourceEdit> get edits =>
      UnmodifiableListView<SourceEdit>([..._edits]);

  /// Current YAML string.
  String _yaml;

  /// Root node of YAML AST.
  YamlNode _contents;

  /// Stores the list of nodes in [_contents] that are connected by aliases.
  Set<YamlNode> _aliases = {};

  @override
  String toString() => _yaml;

  /// Returns the detected indentation level used for this YAML document, or defaults
  /// to a value of `2` if no indentation level can be detected.
  ///
  /// Indentation level is determined by the difference in indentation of the first
  /// block-styled yaml collection in the second level as compared to the top-level
  /// elements. In the case where there are multiple possible candidates, we choose
  /// the candidate closest to the start of [_yaml].
  int get indentation {
    if (_indentation == null) {
      final node = _contents;
      Iterable<YamlNode> children;

      if (node is YamlMap && node.style == CollectionStyle.BLOCK) {
        children = node.nodes.values;
      } else if (node is YamlList && node.style == CollectionStyle.BLOCK) {
        children = node.nodes;
      }

      if (children != null) {
        for (var child in children) {
          var indent = 0;
          if (child is YamlList) {
            indent = getListIndentation(child);
          } else if (child is YamlMap) {
            indent = getMapIndentation(child);
          }

          if (indent != 0) _indentation = indent;
        }
      }
    }

    /// If [_indentation] was not set by the above block, give it a default
    /// value of 2.
    _indentation ??= 2;

    return _indentation;
  }

  int _indentation;

  String get lineEnding {
    if (_isWindowsEnding == null) {
      var index = -1;
      var unixNewlines = 0;
      var windowsNewlines = 0;
      while ((index = _yaml.indexOf('\n', index + 1)) != -1) {
        if (index != 0 && _yaml[index - 1] == '\r') {
          windowsNewlines++;
        } else {
          unixNewlines++;
        }
      }
      _isWindowsEnding = windowsNewlines > unixNewlines;
    }

    return _isWindowsEnding ? '\r\n' : '\n';
  }

  bool _isWindowsEnding;

  factory YamlEditor(String yaml) => YamlEditor._(yaml);

  YamlEditor._(this._yaml) {
    ArgumentError.checkNotNull(_yaml);
    initialize();
  }

  void initialize() {
    _contents = loadYamlNode(_yaml);
    _aliases = {};

    var stack = [_contents];
    var map = <YamlNode, bool>{};

    while (stack.isNotEmpty) {
      var nextElem = stack.removeLast();

      if (map[nextElem] == null) {
        map[nextElem] = true;
      } else {
        _aliases.add(nextElem);
      }

      if (nextElem is YamlMap) {
        stack.addAll(nextElem.nodes.values);
      } else if (nextElem is YamlList) {
        stack.addAll(nextElem.nodes);
      }
    }

    _isWindowsEnding = null;
    _indentation = null;
  }

  /// Parses the document to return [YamlNode] currently present at [path]. If no [YamlNode]s exist
  /// at [path], [parseAt] will return a [YamlNode]-wrapped [orElse] if it is defined, or throw an
  /// [Error] otherwise. The value passed to [orElse] has to be a valid YAML element (i.e. scalar/ list/ map).
  ///
  /// To get `null` when [path] does not point to a value in the [YamlNode]-tree, simply pass `orElse: null`.
  /// ```dart
  /// final myYamlEditor('{"key": "value"}');
  /// final value = myYamlEditor.valueAt(['invalid', 'path'], orElse: null);
  /// print(value) // null
  /// ```
  ///
  /// Common usage example:
  /// ```dart
  ///   final doc = YamlEditor('''
  /// a: 1
  /// b:
  ///   d: 4
  ///   e: [5, 6, 7]
  /// c: 3
  /// ''');
  /// print(doc.parseAt(['b', 'e', 2])); // 7
  /// ```
  ///
  /// To illustrate that [parseAt] returns a [YamlNode] that can be invalidated if modifications are
  /// performed to the document,
  /// ```dart
  /// final doc = YamlEditor("YAML: YAML Ain't Markup Language");
  /// final node = doc.parseAt(['YAML']);
  ///
  /// print(node.value); // Expected output: "YAML Ain't Markup Language"
  ///
  /// doc.assign(['YAML'], 'YAML');
  ///
  /// final newNode = doc.parseAt(['YAML']);
  ///
  /// // Note that the value does not change
  /// print(newNode.value); // "YAML"
  /// print(node.value); // "YAML Ain't Markup Language"
  /// ```
  YamlNode parseAt(Iterable<Object> path, {Object orElse = #noArg}) {
    ArgumentError.checkNotNull(path, 'path');

    try {
      return _traverse(path);
    } on PathError {
      if (orElse == #noArg) rethrow;

      return wrapAsYamlNode(orElse);
    }
  }

  /// Sets [value] in the [path].
  ///
  /// Note that [assign] provides a different result as compared to a [remove] followed by an
  /// [insertIntoList], because it preserves comments at the same level.
  ///
  /// Throws if [path] is invalid.
  ///
  /// ```dart
  /// final doc = YamlEditor('''
  ///   - 0
  ///   - 1 # comment
  ///   - 2
  /// ''');
  /// doc.assign([1], 'test');
  /// ```
  ///
  /// Expected Output:
  /// ```yaml
  ///   - 0
  ///   - test # comment
  ///   - 2
  /// ```
  ///
  /// ```dart
  /// final doc2 = YamlEditor('''
  ///   - 0
  ///   - 1 # comment
  ///   - 2
  /// ''');
  /// doc2.remove([1]);
  /// doc2.insertIntoList([], 1, 'test');
  /// ```
  ///
  /// Expected Output:
  /// ```yaml
  ///   - 0
  ///   - test
  ///   - 2
  /// ```
  void assign(Iterable<Object> path, Object value) {
    ArgumentError.checkNotNull(path, 'path');

    if (path.isEmpty) {
      final start = _contents.span.start.offset;
      final end = getContentSensitiveEnd(_contents);
      final edit =
          SourceEdit(start, end - start, getBlockString(value, 0, lineEnding));

      _performEdit(edit, path, wrapAsYamlNode(value));
      return;
    }

    final pathAsList = path.toList();
    final collectionPath = pathAsList.take(path.length - 1);
    final keyOrIndex = pathAsList.last;
    final parentNode = _traverse(collectionPath, checkAlias: true);

    final valueNode = wrapAsYamlNode(value);

    if (parentNode is YamlList) {
      final expectedList =
          updatedYamlList(parentNode, (nodes) => nodes[keyOrIndex] = valueNode);

      _performEdit(assignInList(this, parentNode, keyOrIndex, value),
          collectionPath, expectedList);
      return;
    }

    if (parentNode is YamlMap) {
      final keyNode = wrapAsYamlNode(keyOrIndex);

      final expectedMap =
          updatedYamlMap(parentNode, (nodes) => nodes[keyNode] = valueNode);
      _performEdit(assignInMap(this, parentNode, keyOrIndex, value),
          collectionPath, expectedMap);
      return;
    }

    throw PathError.unexpected(
        path, 'Scalar $parentNode does not have key $keyOrIndex');
  }

  /// Appends [value] into the list at [path].
  ///
  /// Throws if the element at the given path is not a [YamlList] or if the path is invalid.
  void appendToList(Iterable<Object> path, Object value) {
    ArgumentError.checkNotNull(path, 'path');
    final yamlList = _traverseToList(path);

    insertIntoList(path, yamlList.length, value);
  }

  /// Prepends [value] into the list at [path].
  ///
  /// Throws if the element at the given path is not a [YamlList] or if the path is invalid.
  void prependToList(Iterable<Object> path, Object value) {
    ArgumentError.checkNotNull(path, 'path');

    insertIntoList(path, 0, value);
  }

  /// Inserts [value] into the list at [path], only if the element at the given path
  /// is a list.
  ///
  /// [index] must be non-negative and no greater than the list's length.
  ///
  /// Throws if the element at the given path is not a [YamlList] or if the path is invalid.
  void insertIntoList(Iterable<Object> path, int index, Object value) {
    ArgumentError.checkNotNull(path, 'path');

    final list = _traverseToList(path, checkAlias: true);
    RangeError.checkValueInInterval(index, 0, list.length);

    final edit = insertInList(this, list, index, value);

    final expectedList = updatedYamlList(
        list, (nodes) => nodes.insert(index, wrapAsYamlNode(value)));

    _performEdit(edit, path, expectedList);
  }

  /// Changes the contents of the list at [path] by removing [deleteCount] items at [index], and
  /// inserts [values] in-place.
  ///
  /// [index] and [deleteCount] must be non-negative and, [index] + [deleteCount] must be no
  /// greater than the list's length. Throws otherwise or if [path] is invalid.
  ///
  /// ```dart
  /// final doc = YamlEditor('[Jan, March, April, June]');
  /// doc.spliceList([], 1, 0, ['Feb']); // [Jan, Feb, March, April, June]
  /// doc.spliceList([], 4, 1, ['May']); // [Jan, Feb, March, April, May]
  /// ```
  Iterable<YamlNode> spliceList(Iterable<Object> path, int index,
      int deleteCount, Iterable<Object> values) {
    ArgumentError.checkNotNull(path, 'path');
    ArgumentError.checkNotNull(index, 'index');
    ArgumentError.checkNotNull(deleteCount, 'deleteCount');
    ArgumentError.checkNotNull(values, 'values');

    final list = _traverseToList(path, checkAlias: true);

    RangeError.checkValueInInterval(index, 0, list.length);
    RangeError.checkValueInInterval(index + deleteCount, 0, list.length);

    final nodesToRemove = list.nodes.getRange(index, index + deleteCount);

    /// Perform addition of elements before removal to avoid scenarioes where
    /// a block list gets emptied out to {} to avoid changing collection styles
    /// where possible.

    /// Reverse [values] and insert them.
    final reversedValues = values.toList().reversed;
    for (var value in reversedValues) {
      insertIntoList(path, index, value);
    }

    for (var i = 0; i < deleteCount; i++) {
      remove([...path, index + values.length]);
    }

    return nodesToRemove;
  }

  /// Removes the node at [path].
  ///
  /// Throws if [path] is invalid.
  YamlNode remove(Iterable<Object> path) {
    ArgumentError.checkNotNull(path, 'path');

    SourceEdit edit;
    YamlNode expectedNode;
    var nodeToRemove = _traverse(path, checkAlias: true);

    if (path.isEmpty) {
      edit = SourceEdit(0, _yaml.length, '');

      _performEdit(edit, path, expectedNode);
      return nodeToRemove;
    }

    final pathAsList = path.toList();
    final collectionPath = pathAsList.take(path.length - 1);
    final keyOrIndex = pathAsList.last;
    final parentNode = _traverse(collectionPath);

    if (parentNode is YamlList) {
      edit = removeInList(this, parentNode, keyOrIndex);
      expectedNode =
          updatedYamlList(parentNode, (nodes) => nodes.removeAt(keyOrIndex));
    } else if (parentNode is YamlMap) {
      edit = removeInMap(this, parentNode, keyOrIndex);

      expectedNode =
          updatedYamlMap(parentNode, (nodes) => nodes.remove(keyOrIndex));
    }

    _performEdit(edit, collectionPath, expectedNode);

    return nodeToRemove;
  }

  /// Traverses down [path] to return the [YamlNode] at [path] if successful, throwing an
  /// error otherwise. If [checkAlias] is `true`, throw [AliasError] if an aliased node is
  /// encountered.
  YamlNode _traverse(Iterable<Object> path, {bool checkAlias = false}) {
    ArgumentError.checkNotNull(path, 'path');
    ArgumentError.checkNotNull(checkAlias, 'checkAlias');

    if (path.isEmpty) return _contents;

    var currentNode = _contents;

    for (var keyOrIndex in path) {
      if (currentNode is YamlList) {
        final list = currentNode as YamlList;
        if (!isValidIndex(keyOrIndex, list.length)) {
          throw PathError(path, keyOrIndex, list);
        }

        currentNode = list.nodes[keyOrIndex];
      } else if (currentNode is YamlMap) {
        final map = currentNode as YamlMap;

        if (!containsKey(map, keyOrIndex)) {
          throw PathError(path, keyOrIndex, map);
        }
        final keyNode = getKeyNode(map, keyOrIndex);
        currentNode = map.nodes[keyNode];
      } else {
        throw PathError(path, keyOrIndex, currentNode);
      }
    }

    // We only have to check at the end, because we count children of aliased nodes as aliases too
    if (checkAlias) {
      _assertNoChildAlias(path, currentNode);
    }

    return currentNode;
  }

  /// Asserts that none of the children of [node] are aliases
  void _assertNoChildAlias(Iterable<Object> path, [YamlNode node]) {
    ArgumentError.checkNotNull(path, 'path');

    if (node == null) return _assertNoChildAlias(path, _traverse(path));
    if (_aliases.contains(node)) throw AliasError(path);

    if (node is YamlScalar) return;

    if (node is YamlList) {
      for (var i = 0; i < node.length; i++) {
        var updatedPath = [...path, i];
        _assertNoChildAlias(updatedPath, node.nodes[i]);
      }
    }

    if (node is YamlMap) {
      var keyList = node.keys.toList();
      for (var i = 0; i < node.length; i++) {
        var updatedPath = [...path, keyList[i]];
        _assertNoChildAlias(updatedPath, node.nodes[keyList[i]]);
      }
    }
  }

  /// Traverses down the provided [path] to return the [YamlList] at [path].
  ///
  /// Convenience function to ensure that a [YamlList] is returned.
  ///
  /// Throws if the element at the given path is not a [YamlList] or if the path is invalid.
  /// If [checkAlias] is `true`, and an aliased node is encountered along [path], an error
  /// will be similarly thrown.
  YamlList _traverseToList(Iterable<Object> path, {bool checkAlias = false}) {
    ArgumentError.checkNotNull(path, 'path');
    ArgumentError.checkNotNull(checkAlias, 'checkAlias');

    final possibleList = _traverse(path, checkAlias: true);

    if (possibleList is YamlList) {
      return possibleList;
    } else {
      throw PathError.unexpected(
          path, 'Path $path does not point to a YamlList!');
    }
  }

  /// Utility method to replace the substring of [_yaml] according to [edit].
  ///
  /// When [_yaml] is modified with this method, the resulting string is parsed
  /// and reloaded and traversed down [path] to ensure that the reloaded YAML tree
  /// is equal to our expectations by deep equality of values. Throws an
  /// [AssertionError] if the two trees do not match.
  void _performEdit(
      SourceEdit edit, Iterable<Object> path, YamlNode expectedNode) {
    ArgumentError.checkNotNull(edit, 'edit');
    ArgumentError.checkNotNull(path, 'path');

    final expectedTree = _deepModify(_contents, path, expectedNode);
    _yaml = edit.apply(_yaml);
    initialize();

    final actualTree = loadYamlNode(_yaml);
    if (!deepEquals(actualTree, expectedTree)) {
      throw AssertionError('''
Modification did not result in expected result! 

Obtained: 
$actualTree

Expected: 
$expectedTree''');
    }

    _contents = actualTree;
    _edits.add(edit);
  }

  /// Utility method to produce an updated YAML tree equivalent to converting the [YamlNode]
  /// at [path] to be [expectedNode].
  ///
  /// Throws if path is invalid.
  ///
  /// When called, it creates a new [YamlNode] of the same type as [tree], and copies its children
  /// over, except for the child that is on the path. Doing so allows us to "update" the immutable
  /// [YamlNode] without having to clone the whole tree.
  ///
  /// [SourceSpan]s in this new tree are not guaranteed to be accurate.
  YamlNode _deepModify(
      YamlNode tree, Iterable<Object> path, YamlNode expectedNode) {
    ArgumentError.checkNotNull(path, 'path');
    ArgumentError.checkNotNull(tree, 'tree');

    if (path.isEmpty) return expectedNode;

    final nextPath = path.skip(1);

    if (tree is YamlList) {
      final index = path.first;

      if (!isValidIndex(index, tree.length)) {
        throw PathError(path, index, tree);
      }

      return updatedYamlList(
          tree,
          (nodes) =>
              nodes[index] = _deepModify(nodes[index], nextPath, expectedNode));
    }

    if (tree is YamlMap) {
      final keyNode = wrapAsYamlNode(path.first);
      return updatedYamlMap(
          tree,
          (nodes) => nodes[keyNode] =
              _deepModify(nodes[keyNode], nextPath, expectedNode));
    }

    throw PathError(path, path.first, tree);
  }

  /// Gets the indentation level of [map]. This is 0 if it is a flow map,
  /// but returns the number of spaces before the keys for block maps.
  int getMapIndentation(YamlMap map) {
    ArgumentError.checkNotNull(map, 'map');

    if (map.style == CollectionStyle.FLOW) return 0;

    /// An empty block map doesn't really exist.
    if (map.isEmpty) {
      throw UnsupportedError('Unable to get indentation for empty block map');
    }

    /// Use the number of spaces between the last key and the newline as indentation.
    final lastKey = map.nodes.keys.last as YamlNode;
    final lastSpanOffset = lastKey.span.start.offset;
    final lastNewLine = _yaml.lastIndexOf('\n', lastSpanOffset);
    final lastQuestionMark = _yaml.lastIndexOf('?', lastSpanOffset);

    if (lastQuestionMark == -1) {
      if (lastNewLine == -1) return lastSpanOffset;
      return lastSpanOffset - lastNewLine - 1;
    }

    /// If there is a question mark, it might be a complex key. Check if it
    /// is on the same line as the key node to verify.
    if (lastNewLine == -1) return lastQuestionMark;
    if (lastQuestionMark > lastNewLine) {
      return lastQuestionMark - lastNewLine - 1;
    }

    return lastSpanOffset - lastNewLine - 1;
  }

  /// Gets the indentation level of [list]. This is 0 if it is a flow list,
  /// but returns the number of spaces before the hyphen of elements for
  /// block lists.
  ///
  /// Throws [UnsupportedError] if an empty block map is passed in.
  int getListIndentation(YamlList list) {
    ArgumentError.checkNotNull(list, 'list');

    if (list.style == CollectionStyle.FLOW) return 0;

    /// An empty block map doesn't really exist.
    if (list.isEmpty) {
      throw UnsupportedError('Unable to get indentation for empty block list');
    }

    final lastSpanOffset = list.nodes.last.span.start.offset;
    final lastNewLine = _yaml.lastIndexOf('\n', lastSpanOffset - 1);
    final lastHyphen = _yaml.lastIndexOf('-', lastSpanOffset - 1);

    if (lastNewLine == -1) return lastHyphen;

    return lastHyphen - lastNewLine - 1;
  }
}
