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
class SdkSource extends Source {
  static final SdkSource instance = SdkSource._();

  SdkSource._();

  @override
  final name = 'sdk';

  /// Parses an SDK dependency.
  @override
  PackageRef parseRef(
    String name,
    Object? description, {
    required ResolvedDescription containingDescription,
    LanguageVersion? languageVersion,
  }) {
    if (description is! String) {
      throw const FormatException('The description must be an SDK name.');
    }

    return PackageRef(name, SdkDescription(description));
  }

  @override
  PackageId parseId(
    String name,
    Version version,
    Object? description, {
    String? containingDir,
  }) {
    if (description is! String) {
      throw const FormatException('The description must be an SDK name.');
    }

    return PackageId(
      name,
      version,
      ResolvedSdkDescription(SdkDescription(description)),
    );
  }

  @override
  Future<List<PackageId>> doGetVersions(
    PackageRef ref,
    Duration? maxAge,
    SystemCache cache,
  ) async {
    final description = ref.description;
    if (description is! SdkDescription) {
      throw ArgumentError('Wrong source');
    }
    final pubspec = _loadPubspec(ref, cache);
    final id = PackageId(
      ref.name,
      pubspec.version,
      ResolvedSdkDescription(description),
    );
    // Store the pubspec in memory if we need to refer to it again.
    cache.cachedPubspecs[id] = pubspec;
    return [id];
  }

  @override
  Future<Pubspec> doDescribe(PackageId id, SystemCache cache) async =>
      _loadPubspec(id.toRef(), cache);

  /// Loads the pubspec for the SDK package named [ref].
  ///
  /// Throws a [PackageNotFoundException] if [ref]'s SDK is unavailable or
  /// doesn't contain the package.
  Pubspec _loadPubspec(PackageRef ref, SystemCache cache) {
    final pubspec = Pubspec.load(
      _verifiedPackagePath(ref),
      cache.sources,
      expectedName: ref.name,
      containingDescription: ResolvedSdkDescription(
        ref.description as SdkDescription,
      ),
    );

    /// Validate that there are no non-sdk dependencies if the SDK does not
    /// allow them.
    if (ref.description case final SdkDescription description) {
      if (sdks[description.sdk] case Sdk(
        allowsNonSdkDepsInSdkPackages: false,
      )) {
        for (var dep in pubspec.dependencies.entries) {
          if (dep.value.source is! SdkSource) {
            throw UnsupportedError(
              'Only SDK packages are allowed as regular dependencies for '
              'packages vendored by the ${sdk.identifier} SDK, but the '
              '`${ref.name}` package has a ${dep.value.source.name} dependency '
              'on `${dep.key}`.',
            );
          }
        }
      }
    }
    return pubspec;
  }

  /// Returns the path for the given [ref].
  ///
  /// Throws a [PackageNotFoundException] if [ref]'s SDK is unavailable or
  /// doesn't contain the package.
  String _verifiedPackagePath(PackageRef ref) {
    final description = ref.description;
    if (description is! SdkDescription) {
      throw ArgumentError('Wrong source');
    }
    final sdkName = description.sdk;
    final sdk = sdks[sdkName];
    if (sdk == null) {
      throw PackageNotFoundException('unknown SDK "$sdkName"');
    } else if (!sdk.isAvailable) {
      throw PackageNotFoundException(
        'the ${sdk.name} SDK is not available',
        hint: sdk.installMessage,
      );
    }

    final path = sdk.packagePath(ref.name);
    if (path != null) return path;

    throw PackageNotFoundException(
      'could not find package ${ref.name} in the ${sdk.name} SDK',
    );
  }

  @override
  String doGetDirectory(
    PackageId id,
    SystemCache cache, {
    String? relativeFrom,
  }) {
    try {
      return _verifiedPackagePath(id.toRef());
    } on PackageNotFoundException catch (error) {
      // [PackageNotFoundException]s are uncapitalized and unpunctuated because
      // they're used within other sentences by the version solver, but
      // [ApplicationException]s should be full sentences.
      throw ApplicationException('${capitalize(error.message)}.');
    }
  }
}

class SdkDescription extends Description {
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
  Source get source => SdkSource.instance;

  @override
  int get hashCode => sdk.hashCode;

  @override
  bool operator ==(Object other) {
    return other is SdkDescription && other.sdk == sdk;
  }

  @override
  bool get hasMultipleVersions => false;
}

class ResolvedSdkDescription extends ResolvedDescription {
  @override
  SdkDescription get description => super.description as SdkDescription;

  ResolvedSdkDescription(SdkDescription super.description);

  @override
  Object? serializeForLockfile({required String? containingDir}) {
    return description.sdk;
  }

  @override
  int get hashCode => description.hashCode;

  @override
  bool operator ==(Object other) {
    return other is ResolvedSdkDescription && other.description == description;
  }
}
