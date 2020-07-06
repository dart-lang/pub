// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:yaml/yaml.dart';

import 'editor.dart';
import 'equality.dart';
import 'source_edit.dart';
import 'strings.dart';
import 'utils.dart';

/// Performs the string operation on [yaml] to achieve the effect of setting
/// the element at [key] to [newValue] when re-parsed.
SourceEdit assignInMap(
    YamlEditor yamlEdit, YamlMap map, Object key, Object newValue) {
  ArgumentError.checkNotNull(yamlEdit, 'yamlEdit');
  ArgumentError.checkNotNull(map, 'map');

  if (!containsKey(map, key)) {
    if (map.style == CollectionStyle.FLOW) {
      return _addToFlowMap(yamlEdit, map, key, newValue);
    } else {
      return _addToBlockMap(yamlEdit, map, key, newValue);
    }
  } else {
    if (map.style == CollectionStyle.FLOW) {
      return _replaceInFlowMap(yamlEdit, map, key, newValue);
    } else {
      return _replaceInBlockMap(yamlEdit, map, key, newValue);
    }
  }
}

/// Performs the string operation on [yaml] to achieve the effect of removing
/// the element at [key] when re-parsed.
SourceEdit removeInMap(YamlEditor yamlEdit, YamlMap map, Object key) {
  ArgumentError.checkNotNull(yamlEdit, 'yamlEdit');
  ArgumentError.checkNotNull(map, 'map');

  if (!containsKey(map, key)) return null;

  final keyNode = getKeyNode(map, key);
  final valueNode = map.nodes[keyNode];

  if (map.style == CollectionStyle.FLOW) {
    return _removeFromFlowMap(yamlEdit, map, keyNode, valueNode);
  } else {
    return _removeFromBlockMap(yamlEdit, map, keyNode, valueNode);
  }
}

/// Performs the string operation on [yaml] to achieve the effect of adding
/// the [key]:[newValue] pair when reparsed, bearing in mind that this is a block map.
SourceEdit _addToBlockMap(
    YamlEditor yamlEdit, YamlMap map, Object key, Object newValue) {
  ArgumentError.checkNotNull(yamlEdit, 'yamlEdit');
  ArgumentError.checkNotNull(map, 'map');

  final newIndentation = yamlEdit.getMapIndentation(map) + yamlEdit.indentation;
  final keyString = getFlowString(key);

  var valueString =
      getBlockString(newValue, newIndentation, yamlEdit.lineEnding);
  if (isCollection(newValue) && !isFlowYamlCollectionNode(newValue)) {
    valueString = '${yamlEdit.lineEnding}$valueString';
  }

  var formattedValue = ' ' * yamlEdit.getMapIndentation(map) + '$keyString: ';
  var offset = map.span.end.offset;

  final insertionIndex = getMapInsertionIndex(map, keyString);

  if (map.isNotEmpty) {
    final yaml = yamlEdit.toString();

    // Adjusts offset to after the trailing newline of the last entry, if it exists
    if (insertionIndex == map.length) {
      final lastValueSpanEnd = getContentSensitiveEnd(map.nodes.values.last);
      final nextNewLineIndex = yaml.indexOf('\n', lastValueSpanEnd);

      if (nextNewLineIndex != -1) {
        offset = nextNewLineIndex + 1;
      } else {
        formattedValue = yamlEdit.lineEnding + formattedValue;
      }
    } else {
      final keyAtIndex = map.nodes.keys.toList()[insertionIndex] as YamlNode;
      final keySpanStart = keyAtIndex.span.start.offset;
      final prevNewLineIndex = yaml.lastIndexOf('\n', keySpanStart);

      offset = prevNewLineIndex + 1;
    }
  }

  formattedValue += valueString + yamlEdit.lineEnding;

  return SourceEdit(offset, 0, formattedValue);
}

/// Performs the string operation on [yaml] to achieve the effect of adding
/// the [key]:[newValue] pair when reparsed, bearing in mind that this is a flow map.
SourceEdit _addToFlowMap(
    YamlEditor yamlEdit, YamlMap map, Object key, Object newValue) {
  ArgumentError.checkNotNull(yamlEdit, 'yamlEdit');
  ArgumentError.checkNotNull(map, 'map');

  final keyString = getFlowString(key);
  final valueString = getFlowString(newValue);

  // The -1 accounts for the closing bracket.
  if (map.isEmpty) {
    return SourceEdit(map.span.end.offset - 1, 0, '$keyString: $valueString');
  }

  final insertionIndex = getMapInsertionIndex(map, keyString);

  if (insertionIndex == map.length) {
    return SourceEdit(map.span.end.offset - 1, 0, ', $keyString: $valueString');
  }

  final insertionOffset =
      (map.nodes.keys.toList()[insertionIndex] as YamlNode).span.start.offset;

  return SourceEdit(insertionOffset, 0, '$keyString: $valueString, ');
}

/// Performs the string operation on [yaml] to achieve the effect of replacing
/// the value at [key] with [newValue] when reparsed, bearing in mind that this is a
/// block map.
SourceEdit _replaceInBlockMap(
    YamlEditor yamlEdit, YamlMap map, Object key, Object newValue) {
  ArgumentError.checkNotNull(yamlEdit, 'yamlEdit');
  ArgumentError.checkNotNull(map, 'map');

  final newIndentation = yamlEdit.getMapIndentation(map) + yamlEdit.indentation;
  final value = map.nodes[key];
  final keyNode = getKeyNode(map, key);
  var valueString =
      getBlockString(newValue, newIndentation, yamlEdit.lineEnding);
  if (isCollection(newValue) && !isFlowYamlCollectionNode(newValue)) {
    valueString = yamlEdit.lineEnding + valueString;
  }

  /// +2 accounts for the colon
  final start = keyNode.span.end.offset + 1;
  final end = getContentSensitiveEnd(value);

  return SourceEdit(start, end - start, ' ' + valueString);
}

/// Performs the string operation on [yaml] to achieve the effect of replacing
/// the value at [key] with [newValue] when reparsed, bearing in mind that this is a
/// flow map.
SourceEdit _replaceInFlowMap(
    YamlEditor yamlEdit, YamlMap map, Object key, Object newValue) {
  ArgumentError.checkNotNull(yamlEdit, 'yamlEdit');
  ArgumentError.checkNotNull(map, 'map');

  final valueSpan = map.nodes[key].span;
  final valueString = getFlowString(newValue);

  return SourceEdit(valueSpan.start.offset, valueSpan.length, valueString);
}

/// Performs the string operation on [yaml] to achieve the effect of removing
/// the [key] from the map, bearing in mind that this is a block map.
SourceEdit _removeFromBlockMap(
    YamlEditor yamlEdit, YamlMap map, YamlNode keyNode, YamlNode valueNode) {
  ArgumentError.checkNotNull(yamlEdit, 'yamlEdit');
  ArgumentError.checkNotNull(map, 'map');
  ArgumentError.checkNotNull(keyNode, 'keyNode');
  ArgumentError.checkNotNull(valueNode, 'valueNode');

  final keySpan = keyNode.span;
  final end = getContentSensitiveEnd(valueNode);

  if (map.length == 1) {
    final start = map.span.start.offset;

    return SourceEdit(start, end - start, '{}');
  }

  var yaml = yamlEdit.toString();
  var start = yaml.lastIndexOf('\n', keySpan.start.offset);
  if (start == -1) {
    start = 0;
  } else if (start > 0 && yaml[start - 1] == '\r') {
    start--;
  }
  return SourceEdit(start, end - start, '');
}

/// Performs the string operation on [yaml] to achieve the effect of removing
/// the [key] from the map, bearing in mind that this is a flow map.
SourceEdit _removeFromFlowMap(
    YamlEditor yamlEdit, YamlMap map, YamlNode keyNode, YamlNode valueNode) {
  ArgumentError.checkNotNull(yamlEdit, 'yamlEdit');
  ArgumentError.checkNotNull(map, 'map');
  ArgumentError.checkNotNull(keyNode, 'keyNode');
  ArgumentError.checkNotNull(valueNode, 'valueNode');

  var start = keyNode.span.start.offset;
  var end = valueNode.span.end.offset;
  final yaml = yamlEdit.toString();

  if (deepEquals(keyNode, map.keys.first)) {
    start = yaml.lastIndexOf('{', start - 1) + 1;

    if (deepEquals(keyNode, map.keys.last)) {
      end = yaml.indexOf('}', end);
    } else {
      end = yaml.indexOf(',', end) + 1;
    }
  } else {
    start = yaml.lastIndexOf(',', start - 1);
  }

  return SourceEdit(start, end - start, '');
}
