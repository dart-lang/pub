// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

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

/// An interface for modififying [YAML][1] documents while preserving comments
/// and whitespaces.
///
/// YAML parsing is supported by `package:yaml`, and modifications are performed
/// as string operations. An error will be thrown if internal assertions fail -
/// such a situation should be extremely rare, and should only occur with
/// degenerate formatting.
///
/// Most modification methods require the user to pass in an [Iterable<Object>]
/// path that holds the keys/indices to navigate to the element.
///
/// **Example:**
/// ```yaml
/// a: 1
/// b: 2
/// c:
///   - 3
///   - 4
///   - {e: 5, f: [6, 7]}
/// ```
///
/// To get to `7`, our path will be `['c', 2, 'f', 1]`. The path for the base
/// object is the empty array `[]`. All modification methods will throw a
/// [ArgumentError] if the path provided is invalid. Note also that that the
/// order of elements in the path is important, and it should be arranged in
/// order of calling, with the first element being the first key or index to be
/// called.
///
/// In most modification methods, users are required to pass in a value to be
/// used for updating the YAML tree. This value is only allowed to either be a
/// valid scalar that is recognizable by YAML (i.e. `bool`, `String`, `List`,
/// `Map`, `num`, `null`) or a [YamlNode]. Should the user want to specify
/// the style to be applied to the value passed in, the user may wrap the value
/// using [wrapAsYamlNode] while passing in the appropriate `scalarStyle` or
/// `collectionStyle`. While we try to respect the style that is passed in,
/// there will be instances where the formatting will not result in valid YAML,
/// and as such we will fallback to a default formatting while preserving the
/// content.
///
/// To dump the YAML after all the modifications have been completed, simply
/// call [toString()].
///
/// [1]: https://yaml.org/
@sealed
class YamlEditor {
  final List<SourceEdit> _edits = [];

  /// List of [SourceEdit]s that have been applied to [_yaml] since the creation
  /// of this instance, in chronological order. Intended to be compatible with
  /// `package:analysis_server`.
  ///
  /// The [SourceEdit] objects can be serialized to JSON using the `toJSON`
  /// function, deserialized using [SourceEdit.fromJson], and applied to a
  /// string using the `apply` function. Multiple [SourceEdit]s can be applied
  /// to a string using [SourceEdit.applyAll].
  ///
  /// For more information, refer to the [SourceEdit] class.
  List<SourceEdit> get edits => [..._edits];

  /// Current YAML string.
  String _yaml;

  /// Root node of YAML AST.
  YamlNode _contents;

  /// Stores the list of nodes in [_contents] that are connected by aliases.
  ///
  /// When a node is anchored with an alias and subsequently referenced,
  /// the full content of the anchored node is thought to be copied in the
  /// following references.
  ///
  /// **Example:**
  /// ```dart
  /// a: &SS Sammy Sosa
  /// b: *SS
  /// ```
  ///
  /// is equivalent to
  ///
  /// ```dart
  /// a: Sammy Sosa
  /// b: Sammy Sosa
  /// ```
  ///
  /// As such, aliased nodes have to be treated with special caution when
  /// any modification is taking place.
  ///
  /// See 7.1 Alias Nodes: https://yaml.org/spec/1.2/spec.html#id2786196
  Set<YamlNode> _aliases = {};

  /// Returns the current YAML string.
  @override
  String toString() => _yaml;

  factory YamlEditor(String yaml) => YamlEditor._(yaml);

  YamlEditor._(this._yaml) {
    ArgumentError.checkNotNull(_yaml);
    _initialize();
  }

  /// Loads [_contents] from [_yaml], and traverses the YAML tree formed to
  /// detect alias nodes.
  void _initialize() {
    _contents = loadYamlNode(_yaml);
    _aliases = {};

    /// Performs a DFS on [_contents] to detect alias nodes.
    final visited = <YamlNode>{};
    void collectAliases(YamlNode node) {
      if (visited.add(node)) {
        if (node is YamlMap) {
          node.nodes.forEach((key, value) {
            collectAliases(key);
            collectAliases(value);
          });
        } else if (node is YamlList) {
          node.nodes.forEach(collectAliases);
        }
      } else {
        _aliases.add(node);
      }
    }

    collectAliases(_contents);
  }

  /// Parses the document to return [YamlNode] currently present at [path].
  ///
  /// If no [YamlNode]s exist at [path], the result of invoking the [orElse]
  /// function is returned.
  ///
  /// If [orElse] is omitted, it defaults to throwing a [ArgumentError].
  ///
  /// To get `null` when [path] does not point to a value in the [YamlNode]-tree,
  /// simply pass `orElse: () => null`.
  ///
  /// **Example:** (using orElse)
  /// ```dart
  /// final myYamlEditor('{"key": "value"}');
  /// final value = myYamlEditor.valueAt(['invalid', 'path'], orElse: () => null);
  /// print(value) // null
  /// ```
  ///
  /// **Example:** (common usage)
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
  /// The value returned by [parseAt] is invalidated when the documented is
  /// mutated, as illustrated below:
  ///
  /// **Example:** (old [parseAt] value is invalidated)
  /// ```dart
  /// final doc = YamlEditor("YAML: YAML Ain't Markup Language");
  /// final node = doc.parseAt(['YAML']);
  ///
  /// print(node.value); // Expected output: "YAML Ain't Markup Language"
  ///
  /// doc.update(['YAML'], 'YAML');
  ///
  /// final newNode = doc.parseAt(['YAML']);
  ///
  /// // Note that the value does not change
  /// print(newNode.value); // "YAML"
  /// print(node.value); // "YAML Ain't Markup Language"
  /// ```
  YamlNode parseAt(Iterable<Object> path, {YamlNode Function() orElse}) {
    ArgumentError.checkNotNull(path, 'path');

    return _traverse(path, orElse: orElse);
  }

  /// Sets [value] in the [path].
  ///
  /// There is a subtle difference between [update] and [remove] followed by
  /// an [insertIntoList], because [update] preserves comments at the same level.
  ///
  /// Throws a [ArgumentError] if [path] is invalid.
  ///
  /// **Example:** (using [update])
  /// ```dart
  /// final doc = YamlEditor('''
  ///   - 0
  ///   - 1 # comment
  ///   - 2
  /// ''');
  /// doc.update([1], 'test');
  /// ```
  ///
  /// **Expected Output:**
  /// ```yaml
  ///   - 0
  ///   - test # comment
  ///   - 2
  /// ```
  ///
  /// **Example:** (using [remove] and [insertIntoList])
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
  /// **Expected Output:**
  /// ```yaml
  ///   - 0
  ///   - test
  ///   - 2
  /// ```
  void update(Iterable<Object> path, Object value) {
    ArgumentError.checkNotNull(path, 'path');

    final valueNode = wrapAsYamlNode(value);

    if (path.isEmpty) {
      final start = _contents.span.start.offset;
      final end = getContentSensitiveEnd(_contents);
      final lineEnding = getLineEnding(_yaml);
      final edit = SourceEdit(
          start, end - start, yamlEncodeBlockString(valueNode, 0, lineEnding));

      return _performEdit(edit, path, valueNode);
    }

    final pathAsList = path.toList();
    final collectionPath = pathAsList.take(path.length - 1);
    final keyOrIndex = pathAsList.last;
    final parentNode = _traverse(collectionPath, checkAlias: true);

    if (parentNode is YamlList) {
      final expected = wrapAsYamlNode(
        [...parentNode.nodes]..[keyOrIndex] = valueNode,
      );

      return _performEdit(updateInList(this, parentNode, keyOrIndex, valueNode),
          collectionPath, expected);
    }

    if (parentNode is YamlMap) {
      final expectedMap =
          updatedYamlMap(parentNode, (nodes) => nodes[keyOrIndex] = valueNode);
      return _performEdit(updateInMap(this, parentNode, keyOrIndex, valueNode),
          collectionPath, expectedMap);
    }

    throw PathError.unexpected(
        path, 'Scalar $parentNode does not have key $keyOrIndex');
  }

  /// Appends [value] to the list at [path].
  ///
  /// Throws a [ArgumentError] if the element at the given path is not a
  /// [YamlList] or if the path is invalid.
  ///
  /// **Example:**
  /// ```dart
  /// final doc = YamlEditor('[0, 1]');
  /// doc.appendToList([], 2); // [0, 1, 2]
  /// ```
  void appendToList(Iterable<Object> path, Object value) {
    ArgumentError.checkNotNull(path, 'path');
    final yamlList = _traverseToList(path);

    insertIntoList(path, yamlList.length, value);
  }

  /// Prepends [value] to the list at [path].
  ///
  /// Throws a [ArgumentError] if the element at the given path is not a
  /// [YamlList] or if the path is invalid.
  ///
  /// **Example:**
  /// ```dart
  /// final doc = YamlEditor('[1, 2]');
  /// doc.prependToList([], 0); // [0, 1, 2]
  /// ```
  void prependToList(Iterable<Object> path, Object value) {
    ArgumentError.checkNotNull(path, 'path');

    insertIntoList(path, 0, value);
  }

  /// Inserts [value] into the list at [path].
  ///
  /// [index] must be non-negative and no greater than the list's length.
  ///
  /// Throws a [ArgumentError] if the element at the given path is not a
  /// [YamlList] or if the path is invalid.
  ///
  /// **Example:**
  /// ```dart
  /// final doc = YamlEditor('[0, 2]');
  /// doc.insertIntoList([], 1, 1); // [0, 1, 2]
  /// ```
  void insertIntoList(Iterable<Object> path, int index, Object value) {
    ArgumentError.checkNotNull(path, 'path');
    final valueNode = wrapAsYamlNode(value);

    final list = _traverseToList(path, checkAlias: true);
    RangeError.checkValueInInterval(index, 0, list.length);

    final edit = insertInList(this, list, index, valueNode);
    final expected = wrapAsYamlNode(
      [...list.nodes]..insert(index, valueNode),
    );

    _performEdit(edit, path, expected);
  }

  /// Changes the contents of the list at [path] by removing [deleteCount] items
  /// at [index], and inserting [values] in-place. Returns the elements that
  /// are deleted.
  ///
  /// [index] and [deleteCount] must be non-negative and [index] + [deleteCount]
  /// must be no greater than the list's length.
  ///
  /// Throws a [ArgumentError] if the element at the given path is not a
  /// [YamlList] or if the path is invalid.
  ///
  /// **Example:**
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
    for (final value in reversedValues) {
      insertIntoList(path, index, value);
    }

    for (var i = 0; i < deleteCount; i++) {
      remove([...path, index + values.length]);
    }

    return nodesToRemove;
  }

  /// Removes the node at [path]. Comments "belonging" to the node will be
  /// removed while surrounding comments will be left untouched.
  ///
  /// Throws a [ArgumentError] if [path] is invalid.
  ///
  /// **Example:**
  /// ```dart
  /// final doc = YamlEditor('''
  /// - 0 # comment 0
  /// # comment A
  /// - 1 # comment 1
  /// # comment B
  /// - 2 # comment 2
  /// ''');
  /// doc.remove([1]);
  /// ```
  ///
  /// **Expected Result:**
  /// ```dart
  /// '''
  /// - 0 # comment 0
  /// # comment A
  /// # comment B
  /// - 2 # comment 2
  /// '''
  /// ```
  YamlNode remove(Iterable<Object> path) {
    ArgumentError.checkNotNull(path, 'path');

    SourceEdit edit;
    YamlNode expectedNode;
    final nodeToRemove = _traverse(path, checkAlias: true);

    if (path.isEmpty) {
      edit = SourceEdit(0, _yaml.length, '');

      /// Parsing an empty YAML document returns `null`.
      _performEdit(edit, path, expectedNode);
      return nodeToRemove;
    }

    final pathAsList = path.toList();
    final collectionPath = pathAsList.take(path.length - 1);
    final keyOrIndex = pathAsList.last;
    final parentNode = _traverse(collectionPath);

    if (parentNode is YamlList) {
      edit = removeInList(this, parentNode, keyOrIndex);
      expectedNode = wrapAsYamlNode(
        [...parentNode.nodes]..removeAt(keyOrIndex),
      );
    } else if (parentNode is YamlMap) {
      edit = removeInMap(this, parentNode, keyOrIndex);

      expectedNode =
          updatedYamlMap(parentNode, (nodes) => nodes.remove(keyOrIndex));
    }

    _performEdit(edit, collectionPath, expectedNode);

    return nodeToRemove;
  }

  /// Traverses down [path] to return the [YamlNode] at [path] if successful.
  ///
  /// If no [YamlNode]s exist at [path], the result of invoking the [orElse]
  /// function is returned.
  ///
  /// If [orElse] is omitted, it defaults to throwing a [PathError].
  ///
  /// If [checkAlias] is `true`, throw [AliasError] if an aliased node is
  /// encountered.
  YamlNode _traverse(Iterable<Object> path,
      {bool checkAlias = false, YamlNode Function() orElse}) {
    ArgumentError.checkNotNull(path, 'path');
    ArgumentError.checkNotNull(checkAlias, 'checkAlias');

    if (path.isEmpty) return _contents;

    var currentNode = _contents;
    final pathList = path.toList();

    for (var i = 0; i < pathList.length; i++) {
      final keyOrIndex = pathList[i];

      if (checkAlias && _aliases.contains(currentNode)) {
        throw AliasError(path, currentNode);
      }

      if (currentNode is YamlList) {
        final list = currentNode as YamlList;
        if (!isValidIndex(keyOrIndex, list.length)) {
          return _pathErrorOrElse(path, path.take(i + 1), list, orElse);
        }

        currentNode = list.nodes[keyOrIndex];
      } else if (currentNode is YamlMap) {
        final map = currentNode as YamlMap;

        if (!containsKey(map, keyOrIndex)) {
          return _pathErrorOrElse(path, path.take(i + 1), map, orElse);
        }
        final keyNode = getKeyNode(map, keyOrIndex);

        if (checkAlias) {
          if (_aliases.contains(keyNode)) throw AliasError(path, keyNode);
        }

        currentNode = map.nodes[keyNode];
      } else {
        return _pathErrorOrElse(path, path.take(i + 1), currentNode, orElse);
      }
    }

    if (checkAlias) _assertNoChildAlias(path, currentNode);

    return currentNode;
  }

  /// Throws a [PathError] if [orElse] is not provided, returns the result
  /// of invoking the [orElse] function otherwise.
  YamlNode _pathErrorOrElse(Iterable<Object> path, Iterable<Object> subPath,
      YamlNode parent, YamlNode Function() orElse) {
    if (orElse == null) throw PathError(path, subPath, parent);
    return orElse();
  }

  /// Asserts that [node] and none its children are aliases
  void _assertNoChildAlias(Iterable<Object> path, [YamlNode node]) {
    ArgumentError.checkNotNull(path, 'path');

    if (node == null) return _assertNoChildAlias(path, _traverse(path));
    if (_aliases.contains(node)) throw AliasError(path, node);

    if (node is YamlScalar) return;

    if (node is YamlList) {
      for (var i = 0; i < node.length; i++) {
        final updatedPath = [...path, i];
        _assertNoChildAlias(updatedPath, node.nodes[i]);
      }
    }

    if (node is YamlMap) {
      final keyList = node.keys.toList();
      for (var i = 0; i < node.length; i++) {
        final updatedPath = [...path, keyList[i]];
        if (_aliases.contains(keyList[i])) throw AliasError(path, keyList[i]);
        _assertNoChildAlias(updatedPath, node.nodes[keyList[i]]);
      }
    }
  }

  /// Traverses down the provided [path] to return the [YamlList] at [path].
  ///
  /// Convenience function to ensure that a [YamlList] is returned.
  ///
  /// Throws [ArgumentError] if the element at the given path is not a
  /// [YamlList] or if the path is invalid. If [checkAlias] is `true`, and an
  /// aliased node is encountered along [path], an [AliasError] will be thrown.
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
  /// and reloaded and traversed down [path] to ensure that the reloaded YAML
  /// tree is equal to our expectations by deep equality of values. Throws an
  /// [AssertionError] if the two trees do not match.
  void _performEdit(
      SourceEdit edit, Iterable<Object> path, YamlNode expectedNode) {
    ArgumentError.checkNotNull(edit, 'edit');
    ArgumentError.checkNotNull(path, 'path');

    final expectedTree = _deepModify(_contents, path, [], expectedNode);
    final initialYaml = _yaml;
    _yaml = edit.apply(_yaml);

    try {
      _initialize();
    } on YamlException {
      throw createAssertionError(
          'Failed to produce valid YAML after modification.',
          initialYaml,
          _yaml);
    }

    final actualTree = loadYamlNode(_yaml);
    if (!deepEquals(actualTree, expectedTree)) {
      throw createAssertionError(
          'Modification did not result in expected result.',
          initialYaml,
          _yaml);
    }
    _contents = actualTree;
    _edits.add(edit);
  }

  /// Utility method to produce an updated YAML tree equivalent to converting
  /// the [YamlNode] at [path] to be [expectedNode]. [subPath] holds the portion
  /// of [path] that has been traversed thus far.
  ///
  /// Throws a [PathError] if path is invalid.
  ///
  /// When called, it creates a new [YamlNode] of the same type as [tree], and
  /// copies its children over, except for the child that is on the path. Doing
  /// so allows us to "update" the immutable [YamlNode] without having to clone
  /// the whole tree.
  ///
  /// [SourceSpan]s in this new tree are not guaranteed to be accurate.
  YamlNode _deepModify(YamlNode tree, Iterable<Object> path,
      Iterable<Object> subPath, YamlNode expectedNode) {
    ArgumentError.checkNotNull(path, 'path');
    ArgumentError.checkNotNull(tree, 'tree');
    RangeError.checkValueInInterval(subPath.length, 0, path.length);

    if (path.length == subPath.length) return expectedNode;

    final keyOrIndex = path.elementAt(subPath.length);

    if (tree is YamlList) {
      if (!isValidIndex(keyOrIndex, tree.length)) {
        throw PathError(path, subPath, tree);
      }

      return wrapAsYamlNode([...tree.nodes]..[keyOrIndex] = _deepModify(
          tree.nodes[keyOrIndex],
          path,
          path.take(subPath.length + 1),
          expectedNode));
    }

    if (tree is YamlMap) {
      return updatedYamlMap(
          tree,
          (nodes) => nodes[keyOrIndex] = _deepModify(nodes[keyOrIndex], path,
              path.take(subPath.length + 1), expectedNode));
    }

    /// Should not ever reach here.
    throw PathError(path, subPath, tree);
  }
}
