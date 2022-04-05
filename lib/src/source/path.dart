// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

import '../exceptions.dart';
import '../io.dart';
import '../language_version.dart';
import '../package_name.dart';
import '../pubspec.dart';
import '../source.dart';
import '../system_cache.dart';
import '../utils.dart';

/// A package [Source] that gets packages from a given local file path.
class PathSource extends Source {
  static PathSource instance = PathSource._();
  PathSource._();

  @override
  final name = 'path';

  // /// Returns a reference to a path package named [name] at [path].
  // PackageRef<PathDescription> refFor(String name, String path) {
  //   if (p.isRelative(path)) {
  //     PackageRef(name, {'path':p.absolute(path), 'relative': p.isRelative(path)});
  //   }
  //   return PackageRef(name, {'path': path, 'relative': p.isRelative(path)});
  // }
//{name: myapp, dev_dependencies: {foo: 1.2.2}, dependency_overrides: {foo: {path: ../foo}}, environment: {sdk: >=0.1.2 <1.0.0}}
//{name: myapp, dev_dependencies: {foo: ^1.2.2}, dependency_overrides: {foo: {path: ../foo}}, environment: {sdk: >=0.1.2 <1.0.0}}
  /// Returns an ID for a path package with the given [name] and [version] at
  /// [path].
  ///
  /// If [path] is relative it is resolved relative to [relativeTo]
  PackageId idFor(
      String name, Version version, String path, String relativeTo) {
    return PackageId(
      name,
      version,
      ResolvedPathDescription(
        PathDescription(p.join(relativeTo, path), p.isRelative(path)),
      ),
    );
  }

  /// Parses a path dependency.
  ///
  /// This takes in a path string and returns a map. The "path" key will be the
  /// original path but resolved relative to the containing path. The
  /// "relative" key will be `true` if the original path was relative.
  @override
  PackageRef parseRef(
    String name,
    description, {
    String? containingDir,
    LanguageVersion? languageVersion,
  }) {
    if (description is! String) {
      throw FormatException('The description must be a path string.');
    }
    var dir = description;
    // Resolve the path relative to the containing file path, and remember
    // whether the original path was relative or absolute.
    var isRelative = p.isRelative(description);
    if (isRelative) {
      // Relative paths coming from pubspecs that are not on the local file
      // system aren't allowed. This can happen if a hosted or git dependency
      // has a path dependency.
      if (containingDir == null) {
        throw FormatException('"$description" is a relative path, but this '
            'isn\'t a local pubspec.');
      }

      dir = p.normalize(
        p.absolute(p.join(containingDir, description)),
      );
    }
    return PackageRef(name, PathDescription(dir, isRelative));
  }

  @override
  PackageId parseId(String name, Version version, description,
      {String? containingDir}) {
    if (description is! Map) {
      throw FormatException('The description must be a map.');
    }
    var path = description['path'];
    if (path is! String) {
      throw FormatException("The 'path' field of the description must "
          'be a string.');
    }
    final relative = description['relative'];
    if (relative is! bool) {
      throw FormatException("The 'relative' field of the description "
          'must be a boolean.');
    }

    // Resolve the path relative to the containing file path.
    if (relative) {
      // Relative paths coming from lockfiles that are not on the local file
      // system aren't allowed.
      if (containingDir == null) {
        throw FormatException('"$description" is a relative path, but this '
            'isn\'t a local pubspec.');
      }

      path = p.normalize(
        p.absolute(p.join(containingDir, description['path'])),
      );
    }

    return PackageId(
      name,
      version,
      ResolvedPathDescription(PathDescription(path, relative)),
    );
  }

  /// On both Windows and linux we prefer `/` in the pubspec.lock for relative
  /// paths.
  static String relativePathWithPosixSeparators(String path) {
    assert(p.isRelative(path));
    return p.posix.joinAll(p.split(path));
  }

  @override
  Future<List<PackageId>> doGetVersions(
      PackageRef ref, Duration? maxAge, SystemCache cache) async {
    final description = ref.description;
    if (description is! PathDescription) {
      throw ArgumentError('Wrong source');
    }
    // There's only one package ID for a given path. We just need to find the
    // version.
    var pubspec = _loadPubspec(ref, cache);
    var id = PackageId(
        ref.name, pubspec.version, ResolvedPathDescription(description));
    // Store the pubspec in memory if we need to refer to it again.
    cache.cachedPubspecs[id] = pubspec;
    return [id];
  }

  @override
  Future<Pubspec> doDescribe(PackageId id, SystemCache cache) async =>
      _loadPubspec(id.toRef(), cache);

  Pubspec _loadPubspec(PackageRef ref, SystemCache cache) {
    final description = ref.description;
    if (description is! PathDescription) {
      throw ArgumentError('Wrong source');
    }
    var dir = _validatePath(ref.name, description);
    return Pubspec.load(dir, cache.sources, expectedName: ref.name);
  }

  @override
  String doGetDirectory(
    PackageId id,
    SystemCache cache, {
    String? relativeFrom,
  }) {
    final description = id.description.description;
    if (description is! PathDescription) {
      throw ArgumentError('Wrong source');
    }
    return description.relative
        ? p.relative(description.path, from: relativeFrom)
        : description.path;
  }

  /// Ensures that [description] is a valid path description and returns a
  /// normalized path to the package.
  ///
  /// It must be a map, with a "path" key containing a path that points to an
  /// existing directory. Throws an [ApplicationException] if the path is
  /// invalid.
  String _validatePath(String name, PathDescription description) {
    final dir = description.path;

    if (dirExists(dir)) return dir;

    if (fileExists(dir)) {
      fail('Path dependency for package $name must refer to a directory, '
          'not a file. Was "$dir".');
    }
    throw PackageNotFoundException(
      'could not find package $name at "${description.format()}"',
      innerError: FileException('$dir does not exist.', dir),
    );
  }
}

class PathDescription extends Description {
  final String path;
  final bool relative;

  PathDescription(this.path, this.relative) : assert(!p.isRelative(path));
  @override
  String format() {
    return relative ? p.relative(path) : path;
  }

  @override
  Object? serializeForPubspec({
    required String? containingDir,
    required LanguageVersion languageVersion,
  }) {
    return relative
        ? PathSource.relativePathWithPosixSeparators(
            p.relative(path, from: containingDir))
        : path;
  }

  @override
  Source get source => PathSource.instance;

  @override
  bool operator ==(Object other) {
    return other is PathDescription &&
        canonicalize(path) == canonicalize(other.path);
  }

  @override
  int get hashCode => canonicalize(path).hashCode;
}

class ResolvedPathDescription extends ResolvedDescription {
  @override
  PathDescription get description => super.description as PathDescription;

  ResolvedPathDescription(PathDescription description) : super(description);

  @override
  Object? serializeForLockfile({required String? containingDir}) {
    if (description.relative) {
      return {
        'path': PathSource.relativePathWithPosixSeparators(
          p.relative(description.path, from: containingDir),
        ),
        'relative': true
      };
    }
    return {'path': description.path, 'relative': p.relative('false')};
  }

  @override
  bool operator ==(Object other) =>
      other is ResolvedPathDescription && other.description == description;

  @override
  int get hashCode => description.hashCode;
}
