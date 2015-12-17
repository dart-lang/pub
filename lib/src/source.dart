// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library pub.source;

import 'dart:async';

import 'package:pub_semver/pub_semver.dart';

import 'package.dart';
import 'pubspec.dart';
import 'system_cache.dart';
import 'utils.dart';

/// A source from which to get packages.
///
/// Each source has many packages that it looks up using [PackageId]s. Sources
/// that inherit this directly (currently just [PathSource]) are *uncached*
/// sources. They deliver a package directly to the package that depends on it.
///
/// Other sources are *cached* sources. These extend [CachedSource]. When a
/// package needs a dependency from a cached source, it is first installed in
/// the [SystemCache] and then acquired from there.
///
/// ## Subclassing
///
/// All sources should extend this class. In addition to defining the behavior
/// of various methods, sources define the structure of package descriptions
/// used in [PackageRef]s, [PackageDep]s, and [PackageId]s. There are three
/// distinct types of description, although in practice most sources use the
/// same format for one or more of these:
///
/// * User descriptions. These are included in pubspecs and usually written by
///   hand. They're typically more flexible in the formats they allow to
///   optimize for ease of authoring.
///
/// * Reference descriptions. These are the descriptions in [PackageRef]s and
///   [PackageDep]. They're parsed directly from user descriptions using
///   [parseRef], and so add no additional information.
///
/// * ID descriptions. These are the descriptions in [PackageId]s, which
///   uniquely identify and provide the means to locate the concrete code of a
///   package. They may contain additional expensive-to-compute information
///   relative to the corresponding reference descriptions. These are the
///   descriptions stored in lock files.
abstract class Source {
  /// The name of the source.
  ///
  /// Should be lower-case, suitable for use in a filename, and unique accross
  /// all sources.
  String get name;

  /// Whether this source can choose between multiple versions of the same
  /// package during version solving.
  ///
  /// Defaults to `false`.
  final bool hasMultipleVersions = false;

  /// Whether or not this source is the default source.
  bool get isDefault => systemCache.sources.defaultSource == this;

  /// A cache of pubspecs described by [describe].
  final _pubspecs = <PackageId, Pubspec>{};

  /// The system cache with which this source is registered.
  SystemCache get systemCache {
    assert(_systemCache != null);
    return _systemCache;
  }

  /// The system cache variable.
  ///
  /// Set by [_bind].
  SystemCache _systemCache;

  /// Records the system cache to which this source belongs.
  ///
  /// This should only be called once for each source, by
  /// [SystemCache.register]. It should not be overridden by base classes.
  void bind(SystemCache systemCache) {
    assert(_systemCache == null);
    this._systemCache = systemCache;
  }

  /// Get the IDs of all versions that match [ref].
  ///
  /// Note that this does *not* require the packages to be downloaded locally,
  /// which is the point. This is used during version resolution to determine
  /// which package versions are available to be downloaded (or already
  /// downloaded).
  ///
  /// By default, this assumes that each description has a single version and
  /// uses [describe] to get that version.
  ///
  /// Sources should not override this. Instead, they implement [doGetVersions].
  Future<List<PackageId>> getVersions(PackageRef ref) {
    if (ref.isRoot) {
      throw new ArgumentError("Cannot get versions for the root package.");
    }
    if (ref.source != name) {
      throw new ArgumentError("Package $ref does not use source $name.");
    }

    return doGetVersions(ref);
  }

  /// Get the IDs of all versions that match [ref].
  ///
  /// Note that this does *not* require the packages to be downloaded locally,
  /// which is the point. This is used during version resolution to determine
  /// which package versions are available to be downloaded (or already
  /// downloaded).
  ///
  /// By default, this assumes that each description has a single version and
  /// uses [describe] to get that version.
  ///
  /// This method is effectively protected: subclasses must implement it, but
  /// external code should not call this. Instead, call [getVersions].
  Future<List<PackageId>> doGetVersions(PackageRef ref);

  /// Loads the (possibly remote) pubspec for the package version identified by
  /// [id].
  ///
  /// This may be called for packages that have not yet been downloaded during
  /// the version resolution process. Its results are automatically memoized.
  ///
  /// Throws a [DataException] if the pubspec's version doesn't match [id]'s
  /// version.
  ///
  /// Sources should not override this. Instead, they implement [doDescribe].
  Future<Pubspec> describe(PackageId id) async {
    if (id.isRoot) throw new ArgumentError("Cannot describe the root package.");
    if (id.source != name) {
      throw new ArgumentError("Package $id does not use source $name.");
    }

    var pubspec = _pubspecs[id];
    if (pubspec != null) return pubspec;

    // Delegate to the overridden one.
    pubspec = await doDescribe(id);
    if (pubspec.version != id.version) {
      dataError("The pubspec for $id has version ${pubspec.version}.");
    }

    _pubspecs[id] = pubspec;
    return pubspec;
  }

  /// Loads the (possibly remote) pubspec for the package version identified by
  /// [id].
  ///
  /// This may be called for packages that have not yet been downloaded during
  /// the version resolution process.
  ///
  /// This method is effectively protected: subclasses must implement it, but
  /// external code should not call this. Instead, call [describe].
  Future<Pubspec> doDescribe(PackageId id);

  /// Ensures [id] is available locally and creates a symlink at [symlink]
  /// pointing it.
  Future get(PackageId id, String symlink);

  /// Returns the directory where this package can (or could) be found locally.
  ///
  /// If the source is cached, this will be a path in the system cache.
  String getDirectory(PackageId id);

  /// Parses a [PackageRef] from a name and a user-provided [description].
  ///
  /// When a [Pubspec] is parsed, it reads in the description for each
  /// dependency. It is up to the dependency's [Source] to determine how that
  /// should be interpreted. This will be called during parsing to validate that
  /// the given [description] is well-formed according to this source, and to
  /// give the source a chance to canonicalize the description.
  ///
  /// [containingPath] is the path to the local file (pubspec or lockfile)
  /// where this description appears. It may be `null` if the description is
  /// coming from some in-memory source (such as pulling down a pubspec from
  /// pub.dartlang.org).
  ///
  /// The description in the returned [PackageRef] need bear no resemblance to
  /// the original user-provided description.
  ///
  /// Throws a [FormatException] if the description is not valid.
  PackageRef parseRef(String name, description, {String containingPath});

  /// Parses a [PackageId] from a name and a serialized description.
  ///
  /// This only accepts descriptions serialized using [serializeDescription]. It
  /// should not be used with user-authored descriptions.
  ///
  /// Throws a [FormatException] if the description is not valid.
  PackageId parseId(String name, Version version, description);

  /// When a [LockFile] is serialized, it uses this method to get the
  /// [description] in the right format.
  ///
  /// [containingPath] is the containing directory of the root package.
  dynamic serializeDescription(String containingPath, description) {
    return description;
  }

  /// When a package [description] is shown to the user, this is called to
  /// convert it into a human-friendly form.
  ///
  /// By default, it just converts the description to a string, but sources
  /// may customize this. [containingPath] is the containing directory of the
  /// root package.
  String formatDescription(String containingPath, description) {
    return description.toString();
  }

  /// Returns whether or not [description1] describes the same package as
  /// [description2] for this source.
  ///
  /// This method should be light-weight. It doesn't need to validate that
  /// either package exists.
  ///
  /// Note that either description may be a reference description or an ID
  /// description; they need not be the same type. ID descriptions should be
  /// considered equal to the reference descriptions that produced them.
  bool descriptionsEqual(description1, description2);

  /// Stores [pubspec] so it's returned when [describe] is called with [id].
  ///
  /// This is notionally protected; it should only be called by subclasses.
  void memoizePubspec(PackageId id, Pubspec pubspec) {
    _pubspecs[id] = pubspec;
  }

  /// Returns the source's name.
  String toString() => name;
}
