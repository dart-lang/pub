// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

import 'barback/transformer_config.dart';
import 'compiler.dart';
import 'feature.dart';
import 'io.dart';
import 'package.dart';
import 'package_name.dart';
import 'pubspec.dart';

/// A [Package] whose `lib` directory has been precompiled and cached.
///
/// When users of this class request path information about files that are
/// cached, this returns the cached information. It also wraps the package's
/// pubspec to report no transformers, since the transformations have all been
/// applied already.
class CachedPackage extends Package {
  /// The directory contianing the cached assets from this package.
  ///
  /// Although only `lib` is cached, this directory corresponds to the root of
  /// the package. The actual cached assets exist in `$_cacheDir/lib`.
  final String _cacheDir;

  /// Creates a new cached package wrapping [inner] with the cache at
  /// [_cacheDir].
  CachedPackage(Package inner, this._cacheDir)
      : super(new _CachedPubspec(inner.pubspec), inner.dir);

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

/// A pubspec wrapper that reports no transformers.
class _CachedPubspec implements Pubspec {
  final Pubspec _inner;

  YamlMap get fields => _inner.fields;
  String get name => _inner.name;
  Version get version => _inner.version;
  List<PackageRange> get dependencies => _inner.dependencies;
  List<PackageRange> get devDependencies => _inner.devDependencies;
  List<PackageRange> get dependencyOverrides => _inner.dependencyOverrides;
  Map<String, Feature> get features => _inner.features;
  VersionConstraint get dartSdkConstraint => _inner.dartSdkConstraint;
  VersionConstraint get flutterSdkConstraint => _inner.flutterSdkConstraint;
  String get publishTo => _inner.publishTo;
  Map<String, String> get executables => _inner.executables;
  bool get isPrivate => _inner.isPrivate;
  bool get isEmpty => _inner.isEmpty;
  List<PubspecException> get allErrors => _inner.allErrors;
  Map<String, Compiler> get webCompiler => _inner.webCompiler;

  List<Set<TransformerConfig>> get transformers => const [];

  _CachedPubspec(this._inner);
}
