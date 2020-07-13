// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub_semver/pub_semver.dart';

import 'package_name.dart';
import 'system_cache.dart';

/// Holds the package information
abstract class PackageInfo {
  final String name;
  dynamic get description;

  factory PackageInfo.from(String package,
      {String path, String gitUrl, String gitRef, String gitPath}) {
    ArgumentError.checkNotNull(package, 'package');

    const delimiter = ':';
    final splitPackage = package.split(delimiter);

    /// There shouldn't be more than one `:` in the package information
    if (splitPackage.length > 2) {
      throw PackageParseException(
          'Invalid package and version constraint: $package');
    }

    if (splitPackage.length == 2 &&
        (path != null || gitUrl != null || gitRef != null || gitPath != null)) {
      throw PackageParseException(
          'Cannot declare version constraint and path or git information.');
    }

    var packageName = splitPackage[0];

    if (splitPackage.length == 2) {
      return VersionPackageInfo(
          packageName, VersionConstraint.parse(splitPackage[1]));
    }

    if (path != null) {
      return PathPackageInfo(packageName, path);
    }

    if (gitUrl == null && gitRef == null && gitPath == null) {
      return VersionPackageInfo(packageName, null);
    }

    if (gitUrl == null) {
      throw PackageParseException(
          'Cannot declare git package without declaring git url');
    }

    return GitPackageInfo(packageName, gitUrl, gitRef, gitPath);
  }

  /// Constructs a [packageRange] using the given [cache].
  PackageRange toPackageRange(SystemCache cache);
}

/// Holds the package information for a git package.
class GitPackageInfo implements PackageInfo {
  @override
  final String name;

  /// Package Git information
  Map<String, String> git;

  @override
  dynamic get description => {'git': git};

  GitPackageInfo(this.name, String gitUrl, String gitRef, String gitPath) {
    ArgumentError.checkNotNull(name, 'package name');
    ArgumentError.checkNotNull(gitUrl, 'git url');
    git = {'url': gitUrl};
    if (gitRef != null) git['ref'] = gitRef;
    if (gitPath != null) git['path'] = gitPath;
  }

  @override
  PackageRange toPackageRange(SystemCache cache) {
    return cache.sources['git']
        .parseRef(name, git)
        .withConstraint(VersionRange());
  }
}

class VersionPackageInfo implements PackageInfo {
  @override
  final String name;

  /// Package version constraint
  final VersionConstraint constraint;

  @override
  dynamic get description => constraint?.toString();

  VersionPackageInfo(this.name, this.constraint);

  @override
  PackageRange toPackageRange(SystemCache cache) {
    return PackageRange(name, cache.sources['hosted'],
        constraint ?? VersionConstraint.any, name);
  }
}

class PathPackageInfo implements PackageInfo {
  @override
  final String name;

  /// Path to local package
  final String path;

  @override
  dynamic get description => {'path': path};

  PathPackageInfo(this.name, this.path);

  @override
  PackageRange toPackageRange(SystemCache cache) {
    return cache.sources['path']
        .parseRef(name, path)
        .withConstraint(VersionRange());
  }
}

class PackageParseException implements FormatException {
  @override
  final String message;

  @override
  final int offset;

  @override
  final int source;

  PackageParseException(this.message, [this.offset, this.source]);

  @override
  String toString() => message;
}
