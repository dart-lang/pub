// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

import 'package_name.dart';
import 'system_cache.dart';

/// Holds the package information
abstract class PackageInfo {
  final String name;
  dynamic get description;
  dynamic get pubspecInfo;

  factory PackageInfo.from(String package,
      {String path,
      Map<String, String> git,
      Map<String, String> hostInfo,
      String pubspecPath}) {
    ArgumentError.checkNotNull(package, 'package');

    const delimiter = ':';
    final splitPackage = package.split(delimiter);

    /// There shouldn't be more than one `:` in the package information
    if (splitPackage.length > 2) {
      throw PackageParseException(
          'Invalid package and version constraint: $package');
    }

    if (splitPackage.length == 2 && (path != null || git != null)) {
      throw PackageParseException(
          'Cannot declare version constraint and path or git information.');
    }

    final packageName = splitPackage[0];

    if (splitPackage.length == 2) {
      final constraint = VersionConstraint.parse(splitPackage[1]);

      if (hostInfo == null) {
        return HostedPackageInfo(packageName, constraint: constraint);
      }

      return HostedPackageInfo(packageName,
          constraint: constraint, hostInfo: hostInfo);
    }

    if (path != null) return PathPackageInfo(packageName, path, pubspecPath);
    if (git == null) return HostedPackageInfo(packageName);

    if (git['url'] == null) {
      throw PackageParseException(
          'Cannot declare git package without declaring git url');
    }

    return GitPackageInfo(packageName, git);
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
  dynamic get description {
    return {
      'url': git['url'],
      'ref': git['ref'] ?? 'HEAD',
      'path': git['path'] ?? '.'
    };
  }

  @override
  dynamic get pubspecInfo {
    if (git['ref'] == null && git['path'] == null) {
      return {'git': git['url']};
    }

    return {'git': git};
  }

  GitPackageInfo(this.name, this.git) {
    ArgumentError.checkNotNull(name, 'package name');
    ArgumentError.checkNotNull(git, 'git information');
    ArgumentError.checkNotNull(git['url'], 'git url');
  }

  @override
  PackageRange toPackageRange(SystemCache cache) {
    ArgumentError.checkNotNull(cache, 'cache');
    return cache.sources['git']
        .parseRef(name, git)
        .withConstraint(VersionRange());
  }
}

class HostedPackageInfo implements PackageInfo {
  @override
  final String name;

  /// Package version constraint
  final VersionConstraint constraint;

  /// Information of non-pub.dev package server.
  final Map<String, String> _hostInfo;

  @override
  dynamic get description {
    if (_hostInfo == null) return name;

    return _hostInfo;
  }

  @override
  dynamic get pubspecInfo {
    if (_hostInfo == null) return constraint?.toString();
    if (constraint == null) return {'hosted': _hostInfo};

    return {'hosted': _hostInfo, 'version': constraint.toString()};
  }

  HostedPackageInfo(this.name, {this.constraint, Map<String, String> hostInfo})
      : _hostInfo = hostInfo != null ? {...hostInfo, 'name': name} : null {
    ArgumentError.checkNotNull(name, 'name');
    if (_hostInfo != null) {
      ArgumentError.checkNotNull(hostInfo['url'], 'host url');
    }
  }

  @override
  PackageRange toPackageRange(SystemCache cache) {
    ArgumentError.checkNotNull(cache, 'cache');
    return PackageRange(name, cache.sources['hosted'],
        constraint ?? VersionConstraint.any, description);
  }
}

class PathPackageInfo implements PackageInfo {
  @override
  final String name;

  /// Path to local package
  final String path;

  /// Path to [pubspec.yaml] where `pub` was called.
  final String _pubspecPath;

  @override
  dynamic get description {
    final isRelative = p.isRelative(path);

    return {'path': path, 'relative': isRelative};
  }

  @override
  dynamic get pubspecInfo => {'path': path};

  PathPackageInfo(this.name, this.path, String pubspecPath)
      : _pubspecPath = pubspecPath {
    ArgumentError.checkNotNull(name, 'name');
    ArgumentError.checkNotNull(path, 'path');
  }

  @override
  PackageRange toPackageRange(SystemCache cache) {
    ArgumentError.checkNotNull(cache, 'cache');
    return cache.sources['path']
        .parseRef(name, path, containingPath: _pubspecPath)
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
