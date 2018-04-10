// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:pub_semver/pub_semver.dart';

import '../exceptions.dart';
import '../io.dart';
import '../package_name.dart';
import '../pubspec.dart';
import '../sdk.dart';
import '../source.dart';
import '../system_cache.dart';
import '../utils.dart';

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
    var pubspec = _loadPubspec(ref);
    var id = new PackageId(ref.name, source, pubspec.version, ref.description);
    memoizePubspec(id, pubspec);
    return [id];
  }

  Future<Pubspec> doDescribe(PackageId id) async => _loadPubspec(id);

  /// Loads the pubspec for the Flutter package named [name].
  ///
  /// Throws a [PackageNotFoundException] if [package]'s SDK is unavailable or
  /// doesn't contain the package.
  Pubspec _loadPubspec(PackageName package) =>
      new Pubspec.load(_verifiedPackagePath(package), systemCache.sources,
          expectedName: package.name);

  Future get(PackageId id, String symlink) async {
    createPackageSymlink(id.name, _verifiedPackagePath(id), symlink);
  }

  /// Returns the path for the given [package].
  ///
  /// Throws a [PackageNotFoundException] if [package]'s SDK is unavailable or
  /// doesn't contain the package.
  String _verifiedPackagePath(PackageName package) {
    var identifier = package.description as String;
    var sdk = sdks[identifier];
    if (sdk == null) {
      throw new PackageNotFoundException('unknown SDK "$identifier"');
    } else if (!sdk.isAvailable) {
      throw new PackageNotFoundException("the ${sdk.name} SDK is not available",
          missingSdk: sdk);
    }

    var path = sdk.packagePath(package.name);
    if (path != null) return path;

    throw new PackageNotFoundException(
        'could not find package ${package.name} in the ${sdk.name} SDK');
  }

  String getDirectory(PackageId id) {
    try {
      return _verifiedPackagePath(id);
    } on PackageNotFoundException catch (error) {
      // [PackageNotFoundException]s are uncapitalized and unpunctuated because
      // they're used within other sentences by the version solver, but
      // [ApplicationException]s should be full sentences.
      throw new ApplicationException(capitalize(error.message) + ".");
    }
  }
}
