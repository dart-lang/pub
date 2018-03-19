// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:pub_semver/pub_semver.dart';

import '../exceptions.dart';
import '../flutter.dart' as flutter;
import '../io.dart';
import '../package_name.dart';
import '../pubspec.dart';
import '../source.dart';
import '../system_cache.dart';

/// A package [Source] that gets packages from a hard-coded SDK.
class SdkSource extends Source {
  final name = 'sdk';

  BoundSource bind(SystemCache systemCache) =>
      new BoundSdkSource(this, systemCache);

  /// Returns a reference to an SDK package named [name] from [sdk].
  PackageRef refFor(String name, String sdk) => new PackageRef(name, this, sdk);

  /// Returns an ID for an SDK package with the given [name] and [version] from
  /// [sdk].
  PackageId idFor(String name, Version version, String sdk) =>
      new PackageId(name, this, version, sdk);

  /// Parses an SDK dependency.
  PackageRef parseRef(String name, description, {String containingPath}) {
    if (description is! String) {
      throw new FormatException("The description must be an SDK name.");
    }

    return new PackageRef(name, this, description);
  }

  PackageId parseId(String name, Version version, description,
      {String containingPath}) {
    if (description is! String) {
      throw new FormatException("The description must be an SDK name.");
    }

    return new PackageId(name, this, version, description);
  }

  bool descriptionsEqual(description1, description2) =>
      description1 == description2;

  int hashDescription(description) => description.hashCode;
}

/// The [BoundSource] for [SdkSource].
class BoundSdkSource extends BoundSource {
  final SdkSource source;

  final SystemCache systemCache;

  BoundSdkSource(this.source, this.systemCache);

  Future<List<PackageId>> doGetVersions(PackageRef ref) async {
    var sdk = ref.description as String;
    if (sdk == 'dart') {
      throw new PackageNotFoundException(
          'could not find package ${ref.name} in the Dart SDK');
    } else if (sdk != 'flutter') {
      throw new PackageNotFoundException('unknown SDK "$sdk"');
    }

    var pubspec = _loadPubspec(ref.name);
    var id = new PackageId(ref.name, source, pubspec.version, sdk);
    memoizePubspec(id, pubspec);
    return [id];
  }

  Future<Pubspec> doDescribe(PackageId id) async => _loadPubspec(id.name);

  /// Loads the pubspec for the Flutter package named [name].
  ///
  /// Throws a [PackageNotFoundException] if Flutter is unavaialable or doesn't
  /// contain the package.
  Pubspec _loadPubspec(String name) =>
      new Pubspec.load(_verifiedPackagePath(name), systemCache.sources,
          expectedName: name);

  Future get(PackageId id, String symlink) async {
    createPackageSymlink(id.name, _verifiedPackagePath(id.name), symlink);
  }

  /// Returns the path in the Flutter SDK for the package named [name].
  ///
  /// Throws a [PackageNotFoundException] if Flutter is unavailable or doesn't
  /// contain the package.
  String _verifiedPackagePath(String name) {
    if (!flutter.isAvailable) {
      throw new PackageNotFoundException("the Flutter SDK is not available");
    }

    var path = flutter.packagePath(name);
    if (dirExists(path)) return path;

    throw new PackageNotFoundException(
        'could not find package $name in the Flutter SDK');
  }

  String getDirectory(PackageId id) => flutter.packagePath(id.name);
}
