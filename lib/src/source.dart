// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:pub_semver/pub_semver.dart';

import 'exceptions.dart';
import 'language_version.dart';
import 'lock_file.dart';
import 'package_name.dart';
import 'pubspec.dart';
import 'source/cached.dart';
import 'source/git.dart';
import 'source/hosted.dart';
import 'system_cache.dart';

/// A source from which to get packages.
///
/// Each source has many packages that it looks up using [PackageRef]s.
///
/// Other sources are *cached* sources. These extend [CachedSource]. When a
/// package needs a dependency from a cached source, it is first installed in
/// the [SystemCache] and then acquired from there.
///
/// Methods on [Source] that depends on the cache will take it as an argument.
///
/// ## Types of description
///
/// * Pubspec.yaml descriptions. These are included in pubspecs and usually
///   written by hand. They're typically more flexible in the formats they allow
///   to optimize for ease of authoring.
///
/// * [Description]s. These are the descriptions in [PackageRef]s and
///   [PackageRange]. They're parsed directly from user descriptions using
///   [Source.parseRef]. Internally relative paths are stored absolute, such
///   they can be serialized elsewhere.
///
/// * [ResolvedDescription]s. These are the descriptions in [PackageId]s, which
///   uniquely identify and provide the means to locate the concrete code of a
///   package. They may contain additional expensive-to-compute information
///   relative to the corresponding reference descriptions. These are the
///   descriptions stored in lock files. (This is mainly relevant for the
///   resolved-ref of GitDescriptions.)
abstract class Source {
  /// The name of the source.
  ///
  /// Should be lower-case, suitable for use in a filename, and unique across
  /// all sources.
  String get name;

  /// Parses a [PackageRef] from a name and a user-provided [description].
  ///
  /// When a [Pubspec] is parsed, it reads in the description for each
  /// dependency. It is up to the dependency's [Source] to determine how that
  /// should be interpreted. This will be called during parsing to validate that
  /// the given [description] is well-formed according to this source, and to
  /// give the source a chance to canonicalize the description. For simple
  /// hosted dependencies like `foo:` or `foo: ^1.2.3`, the [description] may
  /// also be `null`.
  ///
  /// [containingDescription] describes the location of the pubspec where this
  /// description appears.
  ///
  /// [languageVersion] is the minimum Dart version parsed from the pubspec's
  /// `environment` field. Source implementations may use this parameter to only
  /// support specific syntax for some versions.
  ///
  /// The description in the returned [PackageRef] need bear no resemblance to
  /// the original user-provided description.
  ///
  /// Throws a [FormatException] if the description is not valid.
  PackageRef parseRef(
    String name,
    Object? description, {
    required ResolvedDescription containingDescription,
    required LanguageVersion languageVersion,
  });

  /// Parses a [PackageId] from a name and a serialized description.
  ///
  /// This should accept descriptions serialized using
  /// [ResolvedDescription.serializeForLockfile].
  ///
  /// [containingDir] is the path to the directory lockfile where this
  /// description appears. It may be `null` if the description is coming from
  /// some in-memory source.
  ///
  /// Throws a [FormatException] if the description is not valid.
  PackageId parseId(
    String name,
    Version version,
    Object? description, {
    String? containingDir,
  });

  /// Returns the source's name.
  @override
  String toString() => name;

  /// Get the IDs of all versions that match [ref].
  ///
  /// Note that this does *not* require the packages to be downloaded locally,
  /// which is the point. This is used during version resolution to determine
  /// which package versions are available to be downloaded (or already
  /// downloaded).
  ///
  /// By default, this assumes that each description has a single version and
  /// uses [SystemCache.describe] to get that version.
  Future<List<PackageId>> doGetVersions(
    PackageRef ref,
    Duration? maxAge,
    SystemCache cache,
  );

  Future<List<Advisory>?>? getAdvisoriesForPackage(
    PackageId id,
    SystemCache cache,
    Duration? maxAge,
  ) {
    return null;
  }

  Future<List<Advisory>?>? getAdvisoriesForPackageVersion(
    PackageId id,
    SystemCache cache,
    Duration? maxAge,
  ) {
    return null;
  }

  /// Loads the (possibly remote) pubspec for the package version identified by
  /// [id].
  ///
  /// For sources that have only one version for a given [PackageRef], this may
  /// return a pubspec with a different version than that specified by [id]. If
  /// they do, [SystemCache.describe] will throw a [PackageNotFoundException].
  ///
  /// This may be called for packages that have not yet been downloaded during
  /// the version resolution process.
  ///
  Future<Pubspec> doDescribe(PackageId id, SystemCache cache);

  /// Returns the directory where this package can (or could) be found locally.
  ///
  /// If the source is cached, this will be a path in the system cache.
  ///
  /// If id is a relative path id, the directory will be relative from
  /// [relativeFrom]. Returns an absolute path if [relativeFrom] is not passed.
  String doGetDirectory(
    PackageId id,
    SystemCache cache, {
    String? relativeFrom,
  });

  /// Returns metadata about a given package-version.
  ///
  /// For remotely hosted packages, the information can be cached for up to
  /// [maxAge]. If [maxAge] is not given, the information is not cached.
  ///
  /// In the case of offline sources, [maxAge] is not used, since information is
  /// per definition cached.
  Future<PackageStatus> status(
    PackageRef ref,
    Version version,
    SystemCache cache, {
    Duration? maxAge,
  }) async {
    return PackageStatus();
  }
}

/// The information needed to get a version-listing of a named package from a
/// [Source].
///
/// For a hosted package this would be the host url.
///
/// For a git package this would be the repo url and a ref and a path inside the
/// repo.
///
/// For a path package it is the path.
///
/// This is the information that goes into a `pubspec.yaml` dependency together
/// with a version constraint.
///
/// After resolution we might know more about the specifics of the package that
/// pins the content down (such as its content-hash or git commit id) this is
/// represented by a [ResolvedDescription].
abstract class Description {
  Source get source;

  /// Whether the source can choose between multiple versions of this
  /// package during version solving.
  bool get hasMultipleVersions;

  Object? serializeForPubspec({
    required String? containingDir,
    required LanguageVersion languageVersion,
  });

  /// Converts `this` into a human-friendly form to show the user.
  ///
  /// Paths are always relative to current dir.
  String format();

  @override
  @mustBeOverridden
  bool operator ==(Object other) =>
      throw UnimplementedError('Subclasses must override');

  @override
  @mustBeOverridden
  int get hashCode => throw UnimplementedError('Subclasses must override');
}

/// A resolved description is a [Description] plus whatever information you need
/// to lock down a specific version.
///
/// This is currently only relevant for the [GitSource] that resolves the
/// [GitDescription.ref] to a specific commit id in [GitSource.doGetVersions].
///
/// This is the information that goes into a `pubspec.lock` file together with
/// a version number (that is represented by a [PackageId].
abstract class ResolvedDescription {
  final Description description;
  ResolvedDescription(this.description);

  /// When a [LockFile] is serialized, it uses this method to get the
  /// [description] in the right format.
  ///
  /// [containingDir] is the containing directory of the root package.
  Object? serializeForLockfile({required String? containingDir});

  /// Converts `this` into a human-friendly form to show the user.
  ///
  /// Paths are always relative to current dir.
  String format() => description.format();

  @override
  @mustBeOverridden
  bool operator ==(Object other) =>
      throw UnimplementedError('Subclasses must override');

  @override
  @mustBeOverridden
  int get hashCode => throw UnimplementedError('Subclasses must override');
}

/// Metadata about a [PackageId].
class PackageStatus {
  /// `null` if not [isDiscontinued]. Otherwise contains the
  /// replacement string provided by the host or `null` if there is no
  /// replacement.
  final String? discontinuedReplacedBy;
  final bool isDiscontinued;
  final bool isRetracted;

  /// The latest point in time at which a security advisory that affects this
  /// package has been synchronized into pub, `null` if this package is not
  /// affected by a security advisory.
  final DateTime? advisoriesUpdated;
  PackageStatus({
    this.isDiscontinued = false,
    this.discontinuedReplacedBy,
    this.isRetracted = false,
    this.advisoriesUpdated,
  });
}
