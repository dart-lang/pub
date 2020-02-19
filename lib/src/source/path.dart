// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

import '../exceptions.dart';
import '../io.dart';
import '../package_name.dart';
import '../pubspec.dart';
import '../source.dart';
import '../system_cache.dart';
import '../utils.dart';

/// A package [Source] that gets packages from a given local file path.
class PathSource extends Source {
  @override
  final name = 'path';

  @override
  BoundSource bind(SystemCache systemCache) =>
      BoundPathSource(this, systemCache);

  /// Given a valid path reference description, returns the file path it
  /// describes.
  ///
  /// This returned path may be relative or absolute and it is up to the caller
  /// to know how to interpret a relative path.
  String pathFromDescription(description) => description['path'];

  /// Returns a reference to a path package named [name] at [path].
  PackageRef refFor(String name, String path) {
    return PackageRef(
        name, this, {'path': path, 'relative': p.isRelative(path)});
  }

  /// Returns an ID for a path package with the given [name] and [version] at
  /// [path].
  PackageId idFor(String name, Version version, String path) {
    return PackageId(
        name, this, version, {'path': path, 'relative': p.isRelative(path)});
  }

  @override
  bool descriptionsEqual(description1, description2) {
    // Compare real paths after normalizing and resolving symlinks.
    var path1 = canonicalize(description1['path']);
    var path2 = canonicalize(description2['path']);
    return path1 == path2;
  }

  @override
  int hashDescription(description) =>
      canonicalize(description['path']).hashCode;

  /// Parses a path dependency.
  ///
  /// This takes in a path string and returns a map. The "path" key will be the
  /// original path but resolved relative to the containing path. The
  /// "relative" key will be `true` if the original path was relative.
  @override
  PackageRef parseRef(String name, description, {String containingPath}) {
    if (description is! String) {
      throw FormatException('The description must be a path string.');
    }

    // Resolve the path relative to the containing file path, and remember
    // whether the original path was relative or absolute.
    var isRelative = p.isRelative(description);
    if (isRelative) {
      // Relative paths coming from pubspecs that are not on the local file
      // system aren't allowed. This can happen if a hosted or git dependency
      // has a path dependency.
      if (containingPath == null) {
        throw FormatException('"$description" is a relative path, but this '
            'isn\'t a local pubspec.');
      }

      description = p.normalize(p.join(p.dirname(containingPath), description));
    }

    return PackageRef(
        name, this, {'path': description, 'relative': isRelative});
  }

  @override
  PackageId parseId(String name, Version version, description,
      {String containingPath}) {
    if (description is! Map) {
      throw FormatException('The description must be a map.');
    }

    if (description['path'] is! String) {
      throw FormatException("The 'path' field of the description must "
          'be a string.');
    }

    if (description['relative'] is! bool) {
      throw FormatException("The 'relative' field of the description "
          'must be a boolean.');
    }

    // Resolve the path relative to the containing file path.
    if (description['relative']) {
      // Relative paths coming from lockfiles that are not on the local file
      // system aren't allowed.
      if (containingPath == null) {
        throw FormatException('"$description" is a relative path, but this '
            'isn\'t a local pubspec.');
      }

      description = Map.from(description);
      description['path'] =
          p.normalize(p.join(p.dirname(containingPath), description['path']));
    }

    return PackageId(name, this, version, description);
  }

  /// Serializes path dependency's [description].
  ///
  /// For the descriptions where `relative` attribute is `true`, tries to make
  /// `path` relative to the specified [containingPath].
  @override
  dynamic serializeDescription(String containingPath, description) {
    if (description['relative']) {
      return {
        'path': relativePathWithPosixSeparators(
            p.relative(description['path'], from: containingPath)),
        'relative': true
      };
    }
    return description;
  }

  /// On both Windows and linux we prefer `/` in the pubspec.lock for relative
  /// paths.
  static String relativePathWithPosixSeparators(String path) {
    assert(p.isRelative(path));
    return p.posix.joinAll(p.split(path));
  }

  /// Converts a parsed relative path to its original relative form.
  @override
  String formatDescription(description) {
    var sourcePath = description['path'];
    if (description['relative']) sourcePath = p.relative(description['path']);
    return sourcePath;
  }
}

/// The [BoundSource] for [PathSource].
class BoundPathSource extends BoundSource {
  @override
  final PathSource source;

  @override
  final SystemCache systemCache;

  BoundPathSource(this.source, this.systemCache);

  @override
  Future<List<PackageId>> doGetVersions(PackageRef ref) async {
    // There's only one package ID for a given path. We just need to find the
    // version.
    var pubspec = _loadPubspec(ref);
    var id = PackageId(ref.name, source, pubspec.version, ref.description);
    memoizePubspec(id, pubspec);
    return [id];
  }

  @override
  Future<Pubspec> doDescribe(PackageId id) async => _loadPubspec(id.toRef());

  Pubspec _loadPubspec(PackageRef ref) {
    var dir = _validatePath(ref.name, ref.description);
    return Pubspec.load(dir, systemCache.sources, expectedName: ref.name);
  }

  @override
  Future get(PackageId id, String symlink) {
    return Future.sync(() {
      var dir = _validatePath(id.name, id.description);
      createPackageSymlink(id.name, dir, symlink,
          relative: id.description['relative']);
    });
  }

  @override
  String getDirectory(PackageId id) => id.description['path'];

  /// Ensures that [description] is a valid path description and returns a
  /// normalized path to the package.
  ///
  /// It must be a map, with a "path" key containing a path that points to an
  /// existing directory. Throws an [ApplicationException] if the path is
  /// invalid.
  String _validatePath(String name, description) {
    var dir = description['path'];

    if (dirExists(dir)) return dir;

    if (fileExists(dir)) {
      fail('Path dependency for package $name must refer to a directory, '
          'not a file. Was "$dir".');
    }

    throw PackageNotFoundException('could not find package $name at "$dir"',
        innerError: FileException('$dir does not exist.', dir));
  }
}
