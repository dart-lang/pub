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
import 'git.dart';
import 'hosted.dart';
import 'root.dart';

/// A package [Source] that gets packages from a given local file path.
class PathSource extends Source {
  static PathSource instance = PathSource._();
  PathSource._();

  @override
  final name = 'path';

  /// Returns an ID for a path package with the given [name] and [version] at
  /// [path].
  ///
  /// If [path] is relative it is resolved relative to [relativeTo]
  PackageId idFor(
    String name,
    Version version,
    String path,
    String relativeTo,
  ) {
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
    Object? description, {
    required ResolvedDescription containingDescription,
    LanguageVersion? languageVersion,
  }) {
    if (description is! String) {
      throw const FormatException('The description must be a path string.');
    }
    final dir = description;
    // Resolve the path relative to the containing file path, and remember
    // whether the original path was relative or absolute.
    final isRelative = p.isRelative(dir);
    if (containingDescription is ResolvedPathDescription) {
      return PackageRef(
        name,
        PathDescription(
          isRelative
              ? p.join(p.absolute(containingDescription.description.path), dir)
              : dir,
          isRelative,
        ),
      );
    } else if (containingDescription is ResolvedRootDescription) {
      return PackageRef(
        name,
        PathDescription(
          isRelative
              ? p.normalize(
                p.join(
                  p.absolute(containingDescription.description.path),
                  description,
                ),
              )
              : description,
          isRelative,
        ),
      );
    } else if (containingDescription is ResolvedGitDescription) {
      if (!isRelative) {
        throw FormatException(
          '"$description" is an absolute path, '
          'it can\'t be referenced from a git pubspec.',
        );
      }
      final resolvedPath = p.url.normalize(
        p.url.joinAll([
          containingDescription.description.path,
          ...p.posix.split(dir),
        ]),
      );
      if (!(p.isWithin('.', resolvedPath) || p.equals('.', resolvedPath))) {
        throw FormatException(
          'the path "$description" '
          'cannot refer outside the git repository $resolvedPath.',
        );
      }
      return PackageRef(
        name,
        GitDescription.raw(
          url: containingDescription.description.url,
          relative: containingDescription.description.relative,
          // Always refer to the same commit as the containing pubspec.
          ref: containingDescription.resolvedRef,
          tagPattern: null,
          path: resolvedPath,
        ),
      );
    } else if (containingDescription is HostedDescription) {
      if (isRelative) {
        throw FormatException(
          '"$description" is a relative path, but this '
          'isn\'t a local pubspec.',
        );
      }
      return PackageRef(name, PathDescription(dir, false));
    } else {
      throw FormatException(
        '"$description" is a path, but this '
        'isn\'t a local pubspec.',
      );
    }
  }

  @override
  PackageId parseId(
    String name,
    Version version,
    Object? description, {
    String? containingDir,
  }) {
    if (description is! Map) {
      throw const FormatException('The description must be a map.');
    }
    var path = description['path'];
    if (path is! String) {
      throw const FormatException(
        "The 'path' field of the description must "
        'be a string.',
      );
    }
    final relative = description['relative'];
    if (relative is! bool) {
      throw const FormatException(
        "The 'relative' field of the description "
        'must be a boolean.',
      );
    }

    // Resolve the path relative to the containing file path.
    if (relative) {
      // Relative paths coming from lockfiles that are not on the local file
      // system aren't allowed.
      if (containingDir == null) {
        throw FormatException(
          '"$description" is a relative path, but this '
          'isn\'t a local pubspec.',
        );
      }

      path = p.normalize(p.absolute(p.join(containingDir, path)));
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
    PackageRef ref,
    Duration? maxAge,
    SystemCache cache,
  ) async {
    final description = ref.description;
    if (description is! PathDescription) {
      throw ArgumentError('Wrong source');
    }
    // There's only one package ID for a given path. We just need to find the
    // version.
    final resolvedDescription = ResolvedPathDescription(description);
    final pubspec = _loadPubspec(ref, resolvedDescription, cache);
    final id = PackageId(ref.name, pubspec.version, resolvedDescription);
    // Store the pubspec in memory if we need to refer to it again.
    cache.cachedPubspecs[id] = pubspec;
    return [id];
  }

  @override
  Future<Pubspec> doDescribe(PackageId id, SystemCache cache) async =>
      _loadPubspec(
        id.toRef(),
        id.description as ResolvedPathDescription,
        cache,
      );

  Pubspec _loadPubspec(
    PackageRef ref,
    ResolvedPathDescription description,
    SystemCache cache,
  ) {
    final dir = _validatePath(ref.name, description.description);
    return Pubspec.load(
      dir,
      cache.sources,
      containingDescription: description,
      expectedName: ref.name,
    );
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
  /// existing directory. Throws an [PackageNotFoundException] if the path is
  /// invalid or a pubspec.yaml file doesn't exist at the location.
  String _validatePath(String name, PathDescription description) {
    final dir = description.path;

    if (dirExists(dir)) {
      final pubspecPath = p.join(dir, 'pubspec.yaml');
      if (!fileExists(pubspecPath)) {
        throw PackageNotFoundException(
          'No pubspec.yaml found for package $name in $dir.',
          innerError: FileException('$pubspecPath doesn\'t exist', pubspecPath),
        );
      }
      return dir;
    }
    if (fileExists(dir)) {
      throw PackageNotFoundException(
        'Path dependency for package $name must refer to a directory, '
        'not a file. Was "$dir".',
        innerError: FileException('$dir is not a directory.', dir),
      );
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

  // Canonicalization is rather slow - cache the result;
  late final String _canonicalizedPath = canonicalize(path);

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
          p.relative(path, from: containingDir),
        )
        : path;
  }

  @override
  Source get source => PathSource.instance;

  @override
  bool operator ==(Object other) {
    return other is PathDescription &&
        _canonicalizedPath == other._canonicalizedPath;
  }

  @override
  int get hashCode => _canonicalizedPath.hashCode;

  @override
  bool get hasMultipleVersions => false;
}

class ResolvedPathDescription extends ResolvedDescription {
  @override
  PathDescription get description => super.description as PathDescription;

  ResolvedPathDescription(PathDescription super.description);

  @override
  Object? serializeForLockfile({required String? containingDir}) {
    if (description.relative) {
      return {
        'path': PathSource.relativePathWithPosixSeparators(
          p.relative(description.path, from: containingDir),
        ),
        'relative': true,
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
