// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:meta/meta.dart';
import 'package:yaml/yaml.dart';

/// Error thrown when a function is passed an invalid path.
@sealed
class PathError extends ArgumentError {
  /// The path that caused the error
  final Iterable<Object> path;

  /// The last element of [path] that could be traversed.
  YamlNode parent;

  PathError(this.path, Object invalidKeyOrIndex, this.parent, [String message])
      : super.value(invalidKeyOrIndex, 'path', message);

  PathError.unexpected(this.path, String message) : super(message);

  @override
  String toString() {
    if (message == null) {
      return 'Invalid path: $path. Missing key or index $invalidValue in parent $parent.';
    }

    return 'Invalid path: $path. $message';
  }
}

/// Error thrown when the path contains an alias along the way.
///
/// When a path contains an aliased node, the behavior becomes less well-defined
/// because we cannot be certain if the user wishes for the change to
/// propagate throughout all the other aliased nodes, or if the user wishes
/// for only that particular node to be modified. As such, [AliasError] reflects
/// the detection that our change will impact an alias, and we do not intend
/// on supporting such changes for the foreseeable future.
@sealed
class AliasError extends UnsupportedError {
  /// The path that caused the error
  final Iterable<Object> path;

  AliasError(this.path)
      : super('Encountered an alias node along $path! '
            'Alias nodes are nodes that refer to a previously serialized nodes, '
            'and are denoted by either the "*" or the "&" indicators in the '
            'original YAML. As the resulting behavior of mutations on these '
            'nodes is not well-defined, the operation will not be supported '
            'by this library.');
}
