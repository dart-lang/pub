// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;

import 'io.dart';
import 'package.dart';

/// A [Package] whose `lib` directory has been precompiled and cached.
///
/// When users of this class request path information about files that are
/// cached, this returns the cached information.
class CachedPackage extends Package {
  /// The directory contianing the cached assets from this package.
  ///
  /// Although only `lib` is cached, this directory corresponds to the root of
  /// the package. The actual cached assets exist in `$_cacheDir/lib`.
  final String _cacheDir;

  /// Creates a new cached package wrapping [inner] with the cache at
  /// [_cacheDir].
  CachedPackage(Package inner, this._cacheDir)
      : super(inner.pubspec, inner.dir);

  String path(String part1,
      [String part2,
      String part3,
      String part4,
      String part5,
      String part6,
      String part7]) {
    if (_pathInCache(part1)) {
      return p.join(_cacheDir, part1, part2, part3, part4, part5, part6, part7);
    } else {
      return super.path(part1, part2, part3, part4, part5, part6, part7);
    }
  }

  String relative(String path) {
    if (p.isWithin(_cacheDir, path)) {
      return p.relative(path, from: _cacheDir);
    }
    return super.relative(path);
  }

  /// This will include the cached, transformed versions of files if [beneath]
  /// is within a cached directory, but not otherwise.
  List<String> listFiles(
      {String beneath, recursive: true, bool useGitIgnore: false}) {
    if (beneath == null) {
      return super.listFiles(recursive: recursive, useGitIgnore: useGitIgnore);
    }

    if (_pathInCache(beneath)) {
      return listDir(p.join(_cacheDir, beneath),
          includeDirs: false, recursive: recursive);
    }
    return super.listFiles(
        beneath: beneath, recursive: recursive, useGitIgnore: useGitIgnore);
  }

  /// Returns whether [relativePath], a path relative to the package's root,
  /// is in a cached directory.
  bool _pathInCache(String relativePath) =>
      relativePath == 'lib' || p.isWithin('lib', relativePath);
}
