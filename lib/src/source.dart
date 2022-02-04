// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:pub_semver/pub_semver.dart';

import 'exceptions.dart';
import 'language_version.dart';
import 'package_name.dart';
import 'pubspec.dart';
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
abstract class Source<T extends Description<T>> {
  /// The name of the source.
  ///
  /// Should be lower-case, suitable for use in a filename, and unique across
  /// all sources.
  String get name;

  /// Whether this source can choose between multiple versions of the same
  /// package during version solving.
  ///
  /// Defaults to `false`.
  bool get hasMultipleVersions => false;

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
  /// [containingDir] is the path to the directory of the pubspec where this
  /// description appears. It may be `null` if the description is coming from
  /// some in-memory source (such as pulling down a pubspec from
  /// pub.dartlang.org).
  ///
  /// [languageVersion] is the minimum Dart version parsed from the pubspec's
  /// `environment` field. Source implementations may use this parameter to only
  /// support specific syntax for some versions.
  ///
  /// The description in the returned [PackageRef] need bear no resemblance to
  /// the original user-provided description.
  ///
  /// Throws a [FormatException] if the description is not valid.
  PackageRef<T> parseRef(
    String name,
    description, {
    String? containingDir,
    required LanguageVersion languageVersion,
  });

  /// Parses a [PackageId] from a name and a serialized description.
  ///
  /// This only accepts descriptions serialized using [serializeDescription]. It
  /// should not be used with user-authored descriptions.
  ///
  /// [containingDir] is the path to the directory lockfile where this
  /// description appears. It may be `null` if the description is coming from
  /// some in-memory source.
  ///
  /// Throws a [FormatException] if the description is not valid.
  PackageId<T> parseId(String name, Version version, description,
      {String? containingDir});

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
  /// uses [describe] to get that version.
  Future<List<PackageId<T>>> doGetVersions(
      PackageRef<T> ref, Duration? maxAge, SystemCache cache);

  /// Loads the (possibly remote) pubspec for the package version identified by
  /// [id].
  ///
  /// For sources that have only one version for a given [PackageRef], this may
  /// return a pubspec with a different version than that specified by [id]. If
  /// they do, [describe] will throw a [PackageNotFoundException].
  ///
  /// This may be called for packages that have not yet been downloaded during
  /// the version resolution process.
  ///
  Future<Pubspec> doDescribe(PackageId<T> id, SystemCache cache);

  /// Returns the directory where this package can (or could) be found locally.
  ///
  /// If the source is cached, this will be a path in the system cache.
  ///
  /// If id is a relative path id, the directory will be relative from
  /// [relativeFrom]. Returns an absolute path if [relativeFrom] is not passed.
  String getDirectory(PackageId<T> id, SystemCache cache,
      {String? relativeFrom});

  /// Returns metadata about a given package.
  ///
  /// For remotely hosted packages, the information can be cached for up to
  /// [maxAge]. If [maxAge] is not given, the information is not cached.
  ///
  /// In the case of offline sources, [maxAge] is not used, since information is
  /// per definiton cached.
  Future<PackageStatus> status(
    PackageId<T> id,
    SystemCache cache, {
    Duration? maxAge,
  }) async =>
      // Default implementation has no metadata.
      PackageStatus();
}

abstract class Description<T extends Description<T>> {
  Source<T> get source;
  Object? serializeForPubspec(
      {required String? containingDir,
      required LanguageVersion languageVersion});

  /// Converts `this` into a human-friendly form to show the user.
  String format({required String? containingDir});
}

abstract class ResolvedDescription<T extends Description<T>> {
  final T description;
  ResolvedDescription(this.description);

  /// When a [LockFile] is serialized, it uses this method to get the
  /// [description] in the right format.
  ///
  /// [containingPath] is the containing directory of the root package.
  Object? serializeForLockfile({required String? containingDir});

  /// Converts `this` into a human-friendly form to show the user.
  String format({required String? containingDir}) =>
      description.format(containingDir: containingDir);
}

/// Metadata about a [PackageId].
class PackageStatus {
  /// `null` if not [isDiscontinued]. Otherwise contains the
  /// replacement string provided by the host or `null` if there is no
  /// replacement.
  final String? discontinuedReplacedBy;
  final bool isDiscontinued;
  final bool isRetracted;
  PackageStatus({
    this.isDiscontinued = false,
    this.discontinuedReplacedBy,
    this.isRetracted = false,
  });
}
