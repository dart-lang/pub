// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Error thrown when a function is passed an invalid path.
class PathError extends ArgumentError {
  /// The path that caused the error
  final Iterable<Object> path;

  /// The last element of [path] that could be traversed.
  Object parentNode;

  PathError(this.path, Object invalidKeyOrIndex, this.parentNode,
      [String message])
      : super.value(invalidKeyOrIndex, 'path', message);

  PathError.unexpected(this.path, String message) : super(message);

  @override
  String toString() {
    if (message == null) {
      return 'Invalid path: $path. Missing key or index $invalidValue in parent $parentNode.';
    }

    return 'Invalid path: $path. $message';
  }
}

/// Error thrown when the path contains an alias along the way.
/// Differs from [PathError] because this extends [UnsupportedError], and
/// may be fixed in the future.
class AliasError extends UnsupportedError {
  /// The path that caused the error
  final Iterable<Object> path;

  AliasError(this.path) : super('Encountered an alias along $path!');
}
