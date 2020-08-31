// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:yaml/yaml.dart';

import 'editor.dart';
import 'equality.dart';
import 'source_edit.dart';
import 'strings.dart';
import 'utils.dart';
import 'wrap.dart';

/// Performs the string operation on [yaml] to achieve the effect of setting
/// the element at [key] to [newValue] when re-parsed.
SourceEdit updateInMap(
    YamlEditor yamlEdit, YamlMap map, Object key, YamlNode newValue) {
  ArgumentError.checkNotNull(yamlEdit, 'yamlEdit');
  ArgumentError.checkNotNull(map, 'map');

  if (!containsKey(map, key)) {
    final keyNode = wrapAsYamlNode(key);

    if (map.style == CollectionStyle.FLOW) {
      return _addToFlowMap(yamlEdit, map, keyNode, newValue);
    } else {
      return _addToBlockMap(yamlEdit, map, keyNode, newValue);
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
/// the [key]:[newValue] pair when reparsed, bearing in mind that this is a
/// block map.
SourceEdit _addToBlockMap(
    YamlEditor yamlEdit, YamlMap map, Object key, YamlNode newValue) {
  ArgumentError.checkNotNull(yamlEdit, 'yamlEdit');
  ArgumentError.checkNotNull(map, 'map');

  final yaml = yamlEdit.toString();
  final newIndentation =
      getMapIndentation(yaml, map) + getIndentation(yamlEdit);
  final keyString = yamlEncodeFlowString(wrapAsYamlNode(key));
  final lineEnding = getLineEnding(yaml);

  var valueString = yamlEncodeBlockString(newValue, newIndentation, lineEnding);
  if (isCollection(newValue) &&
      !isFlowYamlCollectionNode(newValue) &&
      !isEmpty(newValue)) {
    valueString = '$lineEnding$valueString';
  }

  var formattedValue = ' ' * getMapIndentation(yaml, map) + '$keyString: ';
  var offset = map.span.end.offset;

  final insertionIndex = getMapInsertionIndex(map, keyString);

  if (map.isNotEmpty) {
    /// Adjusts offset to after the trailing newline of the last entry, if it
    /// exists
    if (insertionIndex == map.length) {
      final lastValueSpanEnd = getContentSensitiveEnd(map.nodes.values.last);
      final nextNewLineIndex = yaml.indexOf('\n', lastValueSpanEnd);

      if (nextNewLineIndex != -1) {
        offset = nextNewLineIndex + 1;
      } else {
        formattedValue = lineEnding + formattedValue;
      }
    } else {
      final keyAtIndex = map.nodes.keys.toList()[insertionIndex] as YamlNode;
      final keySpanStart = keyAtIndex.span.start.offset;
      final prevNewLineIndex = yaml.lastIndexOf('\n', keySpanStart);

      offset = prevNewLineIndex + 1;
    }
  }

  formattedValue += valueString + lineEnding;

  return SourceEdit(offset, 0, formattedValue);
}

/// Performs the string operation on [yaml] to achieve the effect of adding
/// the [key]:[newValue] pair when reparsed, bearing in mind that this is a flow
/// map.
SourceEdit _addToFlowMap(
    YamlEditor yamlEdit, YamlMap map, YamlNode keyNode, YamlNode newValue) {
  ArgumentError.checkNotNull(yamlEdit, 'yamlEdit');
  ArgumentError.checkNotNull(map, 'map');

  final keyString = yamlEncodeFlowString(keyNode);
  final valueString = yamlEncodeFlowString(newValue);

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
/// the value at [key] with [newValue] when reparsed, bearing in mind that this
/// is a block map.
SourceEdit _replaceInBlockMap(
    YamlEditor yamlEdit, YamlMap map, Object key, YamlNode newValue) {
  ArgumentError.checkNotNull(yamlEdit, 'yamlEdit');
  ArgumentError.checkNotNull(map, 'map');

  final yaml = yamlEdit.toString();
  final lineEnding = getLineEnding(yaml);
  final newIndentation =
      getMapIndentation(yaml, map) + getIndentation(yamlEdit);

  final keyNode = getKeyNode(map, key);
  var valueAsString = yamlEncodeBlockString(
      wrapAsYamlNode(newValue), newIndentation, lineEnding);
  if (isCollection(newValue) &&
      !isFlowYamlCollectionNode(newValue) &&
      !isEmpty(newValue)) {
    valueAsString = lineEnding + valueAsString;
  }

  /// +1 accounts for the colon
  final start = keyNode.span.end.offset + 1;
  var end = getContentSensitiveEnd(map.nodes[key]);

  /// `package:yaml` parses empty nodes in a way where the start/end of the
  /// empty value node is the end of the key node, so we have to adjust for
  /// this.
  if (end < start) end = start;

  return SourceEdit(start, end - start, ' ' + valueAsString);
}

/// Performs the string operation on [yaml] to achieve the effect of replacing
/// the value at [key] with [newValue] when reparsed, bearing in mind that this
/// is a flow map.
SourceEdit _replaceInFlowMap(
    YamlEditor yamlEdit, YamlMap map, Object key, YamlNode newValue) {
  ArgumentError.checkNotNull(yamlEdit, 'yamlEdit');
  ArgumentError.checkNotNull(map, 'map');

  final valueSpan = map.nodes[key].span;
  final valueString = yamlEncodeFlowString(newValue);

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
  var end = getContentSensitiveEnd(valueNode);
  final yaml = yamlEdit.toString();

  if (map.length == 1) {
    final start = map.span.start.offset;
    return SourceEdit(start, end - start, '{}');
  }

  var start = keySpan.start.offset;

  /// Adjust the end to clear the new line after the end too.
  ///
  /// We do this because we suspect that our users will want the inline
  /// comments to disappear too.
  final nextNewLine = yaml.indexOf('\n', end);
  if (nextNewLine != -1) {
    end = nextNewLine + 1;
  }

  final nextNode = getNextKeyNode(map, keyNode);

  if (start > 0) {
    final lastHyphen = yaml.lastIndexOf('-', start - 1);
    final lastNewLine = yaml.lastIndexOf('\n', start - 1);
    if (lastHyphen > lastNewLine) {
      start = lastHyphen + 2;

      /// If there is a `-` before the node, and the end is on the same line
      /// as the next node, we need to add the necessary offset to the end to
      /// make sure the next node has the correct indentation.
      if (nextNode != null &&
          nextNode.span.start.offset - end <= nextNode.span.start.column) {
        end += nextNode.span.start.column;
      }
    } else if (lastNewLine > lastHyphen) {
      start = lastNewLine + 1;
    }
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
