// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:source_span/source_span.dart';
import 'package:yaml/yaml.dart';

/// Determines if [string] is dangerous by checking if parsing the plain string can
/// return a result different from [string].
///
/// This function is also capable of detecting if non-printable characters are in
/// [string].
bool isDangerousString(String string) {
  ArgumentError.checkNotNull(string, 'string');

  try {
    if (loadYamlNode(string).value != string) {
      return true;
    }

    /// [string] should also not contain the `[`, `]`, `,`, `{` and `}` indicator characters.
    return string.contains(RegExp(r'\{|\[|\]|\}|,'));
  } on YamlException {
    return true;
  }
}

/// Asserts that [value] is a valid scalar according to YAML.
///
/// A valid scalar is a number, String, boolean, or null.
void assertValidScalar(Object value) {
  if (value is num || value is String || value is bool || value == null) {
    return;
  }

  throw ArgumentError.value(value, 'value', 'Not a valid scalar type!');
}

/// Checks if [node] is a [YamlNode] with block styling.
///
/// [ScalarStyle.ANY] and [CollectionStyle.ANY] are considered to be block styling
/// by default for maximum flexibility.
bool isBlockNode(YamlNode node) {
  ArgumentError.checkNotNull(node, 'node');

  if (node is YamlScalar) {
    if (node.style == ScalarStyle.LITERAL ||
        node.style == ScalarStyle.FOLDED ||
        node.style == ScalarStyle.ANY) {
      return true;
    }
  }

  if (node is YamlList &&
      (node.style == CollectionStyle.BLOCK ||
          node.style == CollectionStyle.ANY)) return true;
  if (node is YamlMap &&
      (node.style == CollectionStyle.BLOCK ||
          node.style == CollectionStyle.ANY)) return true;

  return false;
}

/// Returns the content sensitive ending offset of [yamlNode] (i.e. where the last
/// meaningful content happens)
int getContentSensitiveEnd(YamlNode yamlNode) {
  ArgumentError.checkNotNull(yamlNode, 'yamlNode');

  if (yamlNode is YamlList) {
    if (yamlNode.style == CollectionStyle.FLOW) {
      return yamlNode.span.end.offset;
    } else {
      return getContentSensitiveEnd(yamlNode.nodes.last);
    }
  } else if (yamlNode is YamlMap) {
    if (yamlNode.style == CollectionStyle.FLOW) {
      return yamlNode.span.end.offset;
    } else {
      return getContentSensitiveEnd(yamlNode.nodes.values.last);
    }
  }

  return yamlNode.span.end.offset;
}

/// Checks if the item is a Map or a List
bool isCollection(Object item) => item is Map || item is List;

/// Checks if [index] is [int], >=0, < [length]
bool isValidIndex(Object index, int length) {
  return index is int && index >= 0 && index < length;
}

/// Creates a [SourceSpan] from [sourceUrl] with no meaningful location
/// information.
///
/// Mainly used with [wrapAsYamlNode] to allow for a reasonable
/// implementation of [SourceSpan.message].
SourceSpan shellSpan(Object sourceUrl) {
  var shellSourceLocation = SourceLocation(0, sourceUrl: sourceUrl);
  return SourceSpanBase(shellSourceLocation, shellSourceLocation, '');
}

/// Returns if [value] is a [YamlList] or [YamlMap] with [CollectionStyle.FLOW].
bool isFlowYamlCollectionNode(Object value) {
  if (value is YamlList || value is YamlMap) {
    return (value as dynamic).style == CollectionStyle.FLOW;
  }

  return false;
}

/// Determines the index where [newKey] will be inserted if the keys in [map] are in
/// alphabetical order when converted to strings.
///
/// Returns the length of [map] if the keys in [map] are not in alphabetical order.
int getMapInsertionIndex(YamlMap map, Object newKey) {
  ArgumentError.checkNotNull(map, 'map');

  final keys = map.nodes.keys.map((k) => k.toString()).toList();

  for (var i = 1; i < keys.length; i++) {
    if (keys[i].compareTo(keys[i - 1]) < 0) {
      return map.length;
    }
  }

  final insertionIndex = keys.indexWhere((key) => key.compareTo(newKey) > 0);

  if (insertionIndex != -1) return insertionIndex;

  return map.length;
}

/// Returns the [style] property of [target], if it is a [YamlNode]. Otherwise return null.
Object getStyle(Object target) {
  if (target is YamlNode) {
    return (target as dynamic).style;
  }

  return null;
}
