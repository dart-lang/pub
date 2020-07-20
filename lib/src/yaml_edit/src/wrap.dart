// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:collection' as collection;
import 'package:collection/collection.dart';
import 'package:source_span/source_span.dart';
import 'package:yaml/yaml.dart';

import 'equality.dart';
import 'utils.dart';

/// Returns a new [YamlMap] constructed by applying [update] onto the [nodes]
/// of this [YamlMap].
YamlMap updatedYamlMap(YamlMap map, Function(Map) update) {
  ArgumentError.checkNotNull(map, 'map');

  final dummyMap = deepEqualsMap();
  dummyMap.addAll(map.nodes);

  update(dummyMap);

  return wrapAsYamlNode(dummyMap);
}

/// Wraps [value] into a [YamlNode].
///
/// [Map]s, [List]s and Scalars will be wrapped as [YamlMap]s, [YamlList]s,
/// and [YamlScalar]s respectively. If [collectionStyle]/[scalarStyle] is
/// defined, and [value] is a collection or scalar, the wrapped [YamlNode] will
/// have the respective style, otherwise it defaults to the ANY style.
///
/// If a [YamlNode] is passed in, no further wrapping will be done, and the
/// [collectionStyle]/[scalarStyle] will not be applied.
YamlNode wrapAsYamlNode(Object value,
    {CollectionStyle collectionStyle = CollectionStyle.ANY,
    ScalarStyle scalarStyle = ScalarStyle.ANY}) {
  if (value is YamlScalar) {
    assertValidScalar(value.value);
    return value;
  } else if (value is YamlList) {
    for (final item in value.nodes) {
      wrapAsYamlNode(item);
    }

    return value;
  } else if (value is YamlMap) {
    /// Both [entry.key] and [entry.values] are guaranteed to be [YamlNode]s,
    /// so running this will just assert that they are valid scalars.
    for (final entry in value.nodes.entries) {
      wrapAsYamlNode(entry.key);
      wrapAsYamlNode(entry.value);
    }

    return value;
  } else if (value is Map) {
    ArgumentError.checkNotNull(collectionStyle, 'collectionStyle');
    return YamlMapWrap(value, collectionStyle: collectionStyle);
  } else if (value is List) {
    ArgumentError.checkNotNull(collectionStyle, 'collectionStyle');
    return YamlListWrap(value, collectionStyle: collectionStyle);
  } else {
    assertValidScalar(value);

    ArgumentError.checkNotNull(scalarStyle, 'scalarStyle');
    return YamlScalarWrap(value, style: scalarStyle);
  }
}

/// Internal class that allows us to define a constructor on [YamlScalar]
/// which takes in [style] as an argument.
class YamlScalarWrap implements YamlScalar {
  /// The [ScalarStyle] to be used for the scalar.
  @override
  final ScalarStyle style;

  @override
  final SourceSpan span;

  @override
  final dynamic value;

  YamlScalarWrap(this.value, {this.style = ScalarStyle.ANY, Object sourceUrl})
      : span = shellSpan(sourceUrl) {
    ArgumentError.checkNotNull(style, 'scalarStyle');
  }

  @override
  String toString() => value.toString();
}

/// Internal class that allows us to define a constructor on [YamlMap]
/// which takes in [style] as an argument.
class YamlMapWrap
    with collection.MapMixin, UnmodifiableMapMixin
    implements YamlMap {
  /// The [CollectionStyle] to be used for the map.
  @override
  final CollectionStyle style;

  @override
  final Map<dynamic, YamlNode> nodes;

  @override
  final SourceSpan span;

  factory YamlMapWrap(Map dartMap,
      {CollectionStyle collectionStyle = CollectionStyle.ANY,
      Object sourceUrl}) {
    ArgumentError.checkNotNull(collectionStyle, 'collectionStyle');

    final wrappedMap = deepEqualsMap<dynamic, YamlNode>();

    for (final entry in dartMap.entries) {
      final wrappedKey = wrapAsYamlNode(entry.key);
      final wrappedValue = wrapAsYamlNode(entry.value);
      wrappedMap[wrappedKey] = wrappedValue;
    }

    return YamlMapWrap._(wrappedMap,
        style: collectionStyle, sourceUrl: sourceUrl);
  }

  YamlMapWrap._(this.nodes,
      {CollectionStyle style = CollectionStyle.ANY, Object sourceUrl})
      : span = shellSpan(sourceUrl),
        style = nodes.isEmpty ? CollectionStyle.FLOW : style;

  @override
  dynamic operator [](Object key) => nodes[key]?.value;

  @override
  Iterable get keys => nodes.keys.map((node) => node.value);

  @override
  Map get value => this;
}

/// Internal class that allows us to define a constructor on [YamlList]
/// which takes in [style] as an argument.
class YamlListWrap with collection.ListMixin implements YamlList {
  /// The [CollectionStyle] to be used for the list.
  @override
  final CollectionStyle style;

  @override
  final List<YamlNode> nodes;

  @override
  final SourceSpan span;

  @override
  int get length => nodes.length;

  @override
  set length(int index) {
    throw UnsupportedError('Cannot modify an unmodifiable List');
  }

  factory YamlListWrap(List dartList,
      {CollectionStyle collectionStyle = CollectionStyle.ANY,
      Object sourceUrl}) {
    ArgumentError.checkNotNull(collectionStyle, 'collectionStyle');

    final wrappedList = dartList.map(wrapAsYamlNode).toList();
    return YamlListWrap._(wrappedList,
        style: collectionStyle, sourceUrl: sourceUrl);
  }

  YamlListWrap._(this.nodes,
      {CollectionStyle style = CollectionStyle.ANY, Object sourceUrl})
      : span = shellSpan(sourceUrl),
        style = nodes.isEmpty ? CollectionStyle.FLOW : style;

  @override
  dynamic operator [](int index) => nodes[index].value;

  @override
  operator []=(int index, value) {
    throw UnsupportedError('Cannot modify an unmodifiable List');
  }

  @override
  List get value => this;
}
