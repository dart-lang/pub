// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:pub_semver/pub_semver.dart';

import '../exceptions.dart';
import '../language_version.dart';
import '../package_name.dart';
import '../pubspec.dart';
import '../sdk.dart';
import '../source.dart';
import '../system_cache.dart';
import '../utils.dart';

/// A package [Source] that gets packages from a hard-coded SDK.
class SdkSource extends Source<SdkDescription> {
  static final SdkSource instance = SdkSource._();

  SdkSource._();

  @override
  final name = 'sdk';

  /// Parses an SDK dependency.
  @override
  PackageRef<SdkDescription> parseRef(String name, description,
      {String? containingDir, LanguageVersion? languageVersion}) {
    if (description is! String) {
      throw FormatException('The description must be an SDK name.');
    }

    return PackageRef(name, SdkDescription(description));
  }

  @override
  PackageId<SdkDescription> parseId(String name, Version version, description,
      {String? containingDir}) {
    if (description is! String) {
      throw FormatException('The description must be an SDK name.');
    }

    return PackageId(
      name,
      version,
      ResolvedSdkDescription(SdkDescription(description)),
    );
  }

  @override
  Future<List<PackageId<SdkDescription>>> doGetVersions(
      PackageRef<SdkDescription> ref,
      Duration? maxAge,
      SystemCache cache) async {
    var pubspec = _loadPubspec(ref, cache);
    var id = PackageId(
      ref.name,
      pubspec.version,
      ResolvedSdkDescription(ref.description),
    );
    // Store the pubspec in memory if we need to refer to it again.
    cache.cachedPubspecs[id] = pubspec;
    return [id];
  }

  @override
  Future<Pubspec> doDescribe(
    PackageId<SdkDescription> id,
    SystemCache cache,
  ) async =>
      _loadPubspec(id.toRef(), cache);

  /// Loads the pubspec for the SDK package named [ref].
  ///
  /// Throws a [PackageNotFoundException] if [ref]'s SDK is unavailable or
  /// doesn't contain the package.
  Pubspec _loadPubspec(PackageRef<SdkDescription> ref, SystemCache cache) =>
      Pubspec.load(_verifiedPackagePath(ref), cache.sources,
          expectedName: ref.name);

  /// Returns the path for the given [package].
  ///
  /// Throws a [PackageNotFoundException] if [package]'s SDK is unavailable or
  /// doesn't contain the package.
  String _verifiedPackagePath(PackageRef<SdkDescription> package) {
    var sdkName = package.description.sdk;
    var sdk = sdks[sdkName];
    if (sdk == null) {
      throw PackageNotFoundException('unknown SDK "$sdkName"');
    } else if (!sdk.isAvailable) {
      throw PackageNotFoundException(
        'the ${sdk.name} SDK is not available',
        hint: sdk.installMessage,
      );
    }

    var path = sdk.packagePath(package.name);
    if (path != null) return path;

    throw PackageNotFoundException(
        'could not find package ${package.name} in the ${sdk.name} SDK');
  }

  @override
  String getDirectory(PackageId<SdkDescription> id, SystemCache cache,
      {String? relativeFrom}) {
    try {
      return _verifiedPackagePath(id.toRef());
    } on PackageNotFoundException catch (error) {
      // [PackageNotFoundException]s are uncapitalized and unpunctuated because
      // they're used within other sentences by the version solver, but
      // [ApplicationException]s should be full sentences.
      throw ApplicationException(capitalize(error.message) + '.');
    }
  }
}

class SdkDescription extends Description<SdkDescription> {
  /// The sdk the described package comes from.
  final String sdk;

  SdkDescription(this.sdk);
  @override
  String format() => sdk;

  @override
  Object? serializeForPubspec({
    required String? containingDir,
    required LanguageVersion languageVersion,
  }) {
    return sdk;
  }

  @override
  Source<SdkDescription> get source => SdkSource.instance;
}

class ResolvedSdkDescription extends ResolvedDescription<SdkDescription> {
  ResolvedSdkDescription(SdkDescription description) : super(description);

  @override
  Object? serializeForLockfile({required String? containingDir}) {
    return description.sdk;
  }
}
