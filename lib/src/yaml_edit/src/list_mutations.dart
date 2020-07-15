// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:yaml/yaml.dart';

import 'editor.dart';
import 'source_edit.dart';
import 'strings.dart';
import 'utils.dart';

/// Returns a [SourceEdit] describing the change to be made on [yaml] to achieve
/// the effect of setting the element at [index] to [newValue] when re-parsed.
SourceEdit updateInList(
    YamlEditor yamlEdit, YamlList list, int index, Object newValue) {
  ArgumentError.checkNotNull(yamlEdit, 'yamlEdit');
  ArgumentError.checkNotNull(list, 'list');
  RangeError.checkValueInInterval(index, 0, list.length - 1);

  final currValue = list.nodes[index];
  final offset = currValue.span.start.offset;
  final yaml = yamlEdit.toString();
  String valueString;

  /// We do not use [_formatNewBlock] since we want to only replace the contents
  /// of this node while preserving comments/whitespace, while [_formatNewBlock]
  /// produces a string represnetation of a new node.
  if (list.style == CollectionStyle.BLOCK) {
    final listIndentation = getListIndentation(yaml, list);
    final indentation = listIndentation + getIndentation(yamlEdit);
    final lineEnding = getLineEnding(yaml);
    valueString = getBlockString(newValue, indentation, lineEnding);

    /// We prefer the compact nested notation for lists
    if (isCollection(newValue)) {
      valueString = valueString.substring(indentation);
    } else if (isCollection(currValue) &&
        getStyle(currValue) == CollectionStyle.BLOCK) {
      /// The span of a block collection in a block list extends until the
      /// next hyphen, so we need to account for this.
      valueString += lineEnding + ' ' * listIndentation;
    }
  } else {
    valueString = getFlowString(newValue);
  }

  return SourceEdit(offset, currValue.span.length, valueString);
}

/// Returns a [SourceEdit] describing the change to be made on [yaml] to achieve
/// the effect of appending [elem] to the list.
SourceEdit appendIntoList(YamlEditor yamlEdit, YamlList list, Object elem) {
  ArgumentError.checkNotNull(yamlEdit, 'yamlEdit');
  ArgumentError.checkNotNull(list, 'list');

  if (list.style == CollectionStyle.FLOW) {
    return _appendToFlowList(yamlEdit, list, elem);
  } else {
    return _appendToBlockList(yamlEdit, list, elem);
  }
}

/// Returns a [SourceEdit] describing the change to be made on [yaml] to achieve
/// the effect of inserting [elem] to the list at [index].
SourceEdit insertInList(
    YamlEditor yamlEdit, YamlList list, int index, Object elem) {
  ArgumentError.checkNotNull(yamlEdit, 'yamlEdit');
  ArgumentError.checkNotNull(list, 'list');
  RangeError.checkValueInInterval(index, 0, list.length);

  /// We call the append method if the user wants to append it to the end of the
  /// list because appending requires different techniques.
  if (index == list.length) {
    return appendIntoList(yamlEdit, list, elem);
  } else {
    if (list.style == CollectionStyle.FLOW) {
      return _insertInFlowList(yamlEdit, list, index, elem);
    } else {
      return _insertInBlockList(yamlEdit, list, index, elem);
    }
  }
}

/// Returns a [SourceEdit] describing the change to be made on [yaml] to achieve
/// the effect of removing the element at [index] when re-parsed.
SourceEdit removeInList(YamlEditor yamlEdit, YamlList list, int index) {
  ArgumentError.checkNotNull(yamlEdit, 'yamlEdit');
  ArgumentError.checkNotNull(list, 'list');

  final nodeToRemove = list.nodes[index];

  if (list.style == CollectionStyle.FLOW) {
    return _removeFromFlowList(yamlEdit, list, nodeToRemove, index);
  } else {
    return _removeFromBlockList(yamlEdit, list, nodeToRemove, index);
  }
}

/// Returns a [SourceEdit] describing the change to be made on [yaml] to achieve
/// the effect of addition [elem] into [nodes], noting that this is a flow list.
SourceEdit _appendToFlowList(YamlEditor yamlEdit, YamlList list, Object elem) {
  ArgumentError.checkNotNull(yamlEdit, 'yamlEdit');
  ArgumentError.checkNotNull(list, 'list');

  final valueString = _formatNewFlow(list, elem, true);
  return SourceEdit(list.span.end.offset - 1, 0, valueString);
}

/// Returns a [SourceEdit] describing the change to be made on [yaml] to achieve
/// the effect of addition [elem] into [nodes], noting that this is a block list.
SourceEdit _appendToBlockList(YamlEditor yamlEdit, YamlList list, Object elem) {
  ArgumentError.checkNotNull(yamlEdit, 'yamlEdit');
  ArgumentError.checkNotNull(list, 'list');

  var formattedValue = _formatNewBlock(yamlEdit, list, elem);
  final yaml = yamlEdit.toString();

  // Adjusts offset to after the trailing newline of the last entry, if it exists
  if (list.isNotEmpty) {
    final lastValueSpanEnd = list.nodes.last.span.end.offset;
    final nextNewLineIndex = yaml.indexOf('\n', lastValueSpanEnd);
    if (nextNewLineIndex == -1) {
      formattedValue = getLineEnding(yaml) + formattedValue;
    }
  }

  return SourceEdit(list.span.end.offset, 0, formattedValue);
}

/// Formats [elem] into a new node for block lists.
String _formatNewBlock(YamlEditor yamlEdit, YamlList list, Object elem) {
  ArgumentError.checkNotNull(yamlEdit, 'yamlEdit');
  ArgumentError.checkNotNull(list, 'list');

  final yaml = yamlEdit.toString();
  final listIndentation = getListIndentation(yaml, list);
  final newIndentation = listIndentation + getIndentation(yamlEdit);
  final lineEnding = getLineEnding(yaml);

  var valueString = getBlockString(elem, newIndentation, lineEnding);
  if (isCollection(elem) && !isFlowYamlCollectionNode(elem)) {
    valueString = valueString.substring(newIndentation);
  }
  final indentedHyphen = ' ' * listIndentation + '- ';

  return '$indentedHyphen$valueString$lineEnding';
}

/// Formats [elem] into a new node for flow lists.
String _formatNewFlow(YamlList list, Object elem, [bool isLast = false]) {
  ArgumentError.checkNotNull(list, 'list');
  ArgumentError.checkNotNull(isLast, 'isLast');

  var valueString = getFlowString(elem);
  if (list.isNotEmpty) {
    if (isLast) {
      valueString = ', $valueString';
    } else {
      valueString += ', ';
    }
  }

  return valueString;
}

/// Returns a [SourceEdit] describing the change to be made on [yaml] to achieve
/// the effect of inserting [elem] into [nodes] at [index], noting that this is
/// a block list.
///
/// [index] should be non-negative and less than or equal to [length].
SourceEdit _insertInBlockList(
    YamlEditor yamlEdit, YamlList list, int index, Object elem) {
  ArgumentError.checkNotNull(yamlEdit, 'yamlEdit');
  ArgumentError.checkNotNull(list, 'list');
  RangeError.checkValueInInterval(index, 0, list.length);

  if (index == list.length) return _appendToBlockList(yamlEdit, list, elem);

  final formattedValue = _formatNewBlock(yamlEdit, list, elem);

  final currNode = list.nodes[index];
  final currNodeStart = currNode.span.start.offset;
  final yaml = yamlEdit.toString();
  final start = yaml.lastIndexOf('\n', currNodeStart) + 1;

  return SourceEdit(start, 0, formattedValue);
}

/// Returns a [SourceEdit] describing the change to be made on [yaml] to achieve
/// the effect of inserting [elem] into [nodes] at [index], noting that this is
/// a flow list.
///
/// [index] should be non-negative and less than or equal to [length].
SourceEdit _insertInFlowList(
    YamlEditor yamlEdit, YamlList list, int index, Object elem) {
  ArgumentError.checkNotNull(yamlEdit, 'yamlEdit');
  ArgumentError.checkNotNull(list, 'list');
  RangeError.checkValueInInterval(index, 0, list.length);

  if (index == list.length) return _appendToFlowList(yamlEdit, list, elem);

  final formattedValue = _formatNewFlow(list, elem);

  final yaml = yamlEdit.toString();
  final currNode = list.nodes[index];
  final currNodeStart = currNode.span.start.offset;
  var start = yaml.lastIndexOf(RegExp(r',|\['), currNodeStart - 1) + 1;
  if (yaml[start] == ' ') start++;

  return SourceEdit(start, 0, formattedValue);
}

/// Returns a [SourceEdit] describing the change to be made on [yaml] to achieve
/// the effect of removing [nodeToRemove] from [nodes], noting that this is a
/// block list.
///
/// [index] should be non-negative and less than or equal to [length].
SourceEdit _removeFromBlockList(
    YamlEditor yamlEdit, YamlList list, YamlNode removedNode, int index) {
  ArgumentError.checkNotNull(yamlEdit, 'yamlEdit');
  ArgumentError.checkNotNull(list, 'list');
  RangeError.checkValueInInterval(index, 0, list.length - 1);

  /// If we are removing the last element in a block list, convert it into a
  /// flow empty list.
  if (list.length == 1) {
    final start = list.span.start.offset;
    final end = getContentSensitiveEnd(removedNode);

    return SourceEdit(start, end - start, '[]');
  }

  final span = removedNode.span;
  final yaml = yamlEdit.toString();
  var start = yaml.lastIndexOf('\n', span.start.offset);
  var end = yaml.indexOf('\n', span.end.offset);

  if (start == -1) start = 0;
  if (end == -1) {
    end = yaml.length;
  }

  return SourceEdit(start, end - start, '');
}

/// Returns a [SourceEdit] describing the change to be made on [yaml] to achieve
/// the effect of removing [nodeToRemove] from [nodes], noting that this is a
/// flow list.
///
/// [index] should be non-negative and less than or equal to [length].
SourceEdit _removeFromFlowList(
    YamlEditor yamlEdit, YamlList list, YamlNode nodeToRemove, int index) {
  ArgumentError.checkNotNull(yamlEdit, 'yamlEdit');
  ArgumentError.checkNotNull(list, 'list');
  RangeError.checkValueInInterval(index, 0, list.length - 1);

  final span = nodeToRemove.span;
  final yaml = yamlEdit.toString();
  var start = span.start.offset;
  var end = span.end.offset;

  if (index == 0) {
    start = yaml.lastIndexOf('[', start - 1) + 1;
    if (index == list.length - 1) {
      end = yaml.indexOf(']', end);
    } else {
      end = yaml.indexOf(',', end) + 1;
    }
  } else {
    start = yaml.lastIndexOf(',', start - 1);
  }

  return SourceEdit(start, end - start, '');
}
