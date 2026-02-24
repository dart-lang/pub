// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:path/path.dart' as path;

/// A default [path.Context] for use in `pub` code.
path.Context get p =>
    Zone.current[_pathContextKey] as path.Context? ?? path.context;

/// The key for the [path.Context] in the current [Zone].
final _pathContextKey = Object();

/// Runs [callback] in a [Zone] where [p] is overridden by [pathContext].
R withPathContext<R>(
  R Function() callback, {
  required path.Context pathContext,
}) => runZoned(callback, zoneValues: {_pathContextKey: pathContext});

extension PathContextExt on path.Context {
  /// A default context for manipulating POSIX paths.
  path.Context get posix => path.posix;

  /// A default context for manipulating URLs.
  ///
  /// URL path equality is undefined for paths that differ only in their
  /// percent-encoding or only in the case of their host segment.
  path.Context get url => path.url;
}
