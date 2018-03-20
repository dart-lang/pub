// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:async/async.dart';
import 'package:collection/collection.dart';
import 'package:pub_semver/pub_semver.dart';

import '../flutter.dart' as flutter;
import '../package.dart';
import '../package_name.dart';
import '../pubspec.dart';
import '../sdk.dart' as sdk;
import '../source.dart';
import '../system_cache.dart';
import '../utils.dart';
import 'incompatibility.dart';
import 'incompatibility_cause.dart';
import 'term.dart';

/// A cache of all the versions of a single package that provides information
/// about those versions to the solver.
class PackageLister {
  /// The package that is being listed.
  final PackageRef _ref;

  /// The version of this package in the lockfile.
  ///
  /// This is `null` if this package isn't locked or if the current version
  /// solve isn't a `pub get`.
  final PackageId _locked;

  /// The source from which [_ref] comes.
  final BoundSource _source;

  /// The set of package names that were overridden by the root package.
  final Set<String> _overriddenPackages;

  /// Whether this is a downgrade, in which case the package priority should be
  /// reversed.
  final bool _isDowngrade;

  /// A map from dependency names to constraints indicating which versions of
  /// [_ref] have already had their dependencies on the given versions returned
  /// by [incompatibilitiesFor].
  ///
  /// This allows us to avoid returning the same incompatibilities multiple
  /// times.
  final _alreadyListedDependencies = <String, VersionConstraint>{};

  /// A constraint indicating which versions of [_ref] are already known to be
  /// incompatible with the current version of the SDK.
  ///
  /// This allows us to avoid returning the same incompatibilities from
  /// [incompatibilitiesFor] multiple times.
  var _knownInvalidSdks = VersionConstraint.empty;

  /// Whether we've returned incompatibilities for [_locked].
  var _listedLockedVersion = false;

  /// The versions of [_ref] that have been downloaded and cached, or `null` if
  /// they haven't been downloaded yet.
  List<PackageId> get cachedVersions => _versionsCache?.result?.asValue?.value;

  /// All versions of the package, sorted by [Version.compareTo].
  Future<List<PackageId>> get _versions {
    _versionsCache ??=
        new ResultFuture(_source.getVersions(_ref).then((versions) {
      versions.sort((id1, id2) => id1.version.compareTo(id2.version));
      return versions;
    }));
    return _versionsCache;
  }

  ResultFuture<List<PackageId>> _versionsCache;

  /// Creates a package lister for the dependency identified by [ref].
  PackageLister(
      SystemCache cache, this._ref, this._locked, this._overriddenPackages,
      {bool downgrade: false})
      : _source = cache.source(_ref.source),
        _isDowngrade = downgrade;

  /// Creates a package lister for the root [package].
  PackageLister.root(Package package)
      : _ref = new PackageRef.root(package),
        _source = new _RootSource(package),
        // Treat the package as locked so we avoid the logic for finding the
        // boundaries of various constraints, which is useless for the root
        // package.
        _locked = new PackageId.root(package),
        _overriddenPackages = const UnmodifiableSetView.empty(),
        _isDowngrade = false;

  /// Returns the number of versions of this package that match [constraint].
  Future<int> countVersions(VersionConstraint constraint) async {
    if (_locked != null && constraint.allows(_locked.version)) return 1;
    return (await _versions)
        .where((id) => constraint.allows(id.version))
        .length;
  }

  /// Returns the best version of this package that matches [constraint]
  /// according to the solver's prioritization scheme, or `null` if no versions
  /// match.
  Future<PackageId> bestVersion(VersionConstraint constraint) async {
    if (_locked != null && constraint.allows(_locked.version)) return _locked;

    var versions = await _versions;

    // If [constraint] has a minimum (or a maximum in downgrade mode), we can
    // bail early once we're past it.
    var isPastLimit = (Version _) => false;
    if (constraint is VersionRange) {
      if (_isDowngrade) {
        var max = constraint.max;
        if (max != null) isPastLimit = (version) => version > max;
      } else {
        var min = constraint.min;
        if (min != null) isPastLimit = (version) => version < min;
      }
    }

    // Return the most preferable version that matches [constraint]: the latest
    // non-prerelease version if one exists, or the latest prerelease version
    // otherwise.
    PackageId bestPrerelease;
    for (var id in _isDowngrade ? versions : versions.reversed) {
      if (isPastLimit != null && isPastLimit(id.version)) break;

      if (!constraint.allows(id.version)) continue;
      if (!id.version.isPreRelease) return id;
      bestPrerelease ??= id;
    }
    return bestPrerelease;
  }

  /// Returns incompatibilities that encapsulate [id]'s dependencies, or that
  /// indicate that it can't be safely selected.
  ///
  /// If multiple subsequent versions of this package have the same
  /// dependencies, this will return incompatibilities that reflect that. It
  /// won't return incompatibilities that have already been returned by a
  /// previous call to [incompatibilitiesFor].
  Future<List<Incompatibility>> incompatibilitiesFor(PackageId id) async {
    if (_knownInvalidSdks.allows(id.version)) return const [];

    var pubspec = await _source.describe(id);
    if (_versionsCache == null &&
        _locked != null &&
        id.version == _locked.version) {
      if (_listedLockedVersion) return const [];
      _listedLockedVersion = true;
      if (!_matchesDartSdkConstraint(pubspec)) {
        return [
          new Incompatibility(
              [new Term(id, true)], new SdkCause(pubspec.dartSdkConstraint))
        ];
      } else if (!_matchesFlutterSdkConstraint(pubspec)) {
        return [
          new Incompatibility([new Term(id, true)],
              new SdkCause(pubspec.flutterSdkConstraint, flutter: true))
        ];
      } else {
        var dependencies = id.isRoot
            ? (new Map.from(pubspec.dependencies)
              ..addAll(pubspec.devDependencies)
              ..addAll(pubspec.dependencyOverrides))
            : pubspec.dependencies;
        return dependencies.values
            .map((range) => new Incompatibility(
                [new Term(id, true), new Term(range, false)],
                IncompatibilityCause.dependency))
            .toList();
      }
    }

    var versions = await _versions;
    var index = indexWhere(versions, (other) => identical(id, other));

    var dartSdkIncompatibility = await _checkSdkConstraint(index);
    if (dartSdkIncompatibility != null) return [dartSdkIncompatibility];

    var flutterSdkIncompatibility =
        await _checkSdkConstraint(index, flutter: true);
    if (flutterSdkIncompatibility != null) return [flutterSdkIncompatibility];

    // Don't recompute dependencies that have already been emitted.
    var dependencies = new Map<String, PackageRange>.from(pubspec.dependencies);
    for (var package in dependencies.keys.toList()) {
      if (_overriddenPackages.contains(package)) {
        dependencies.remove(package);
        continue;
      }

      var constraint = _alreadyListedDependencies[package];
      if (constraint != null && constraint.allows(id.version)) {
        dependencies.remove(package);
      }
    }

    var lower = await _dependencyBounds(dependencies, index, upper: false);
    var upper = await _dependencyBounds(dependencies, index, upper: true);

    return ordered(dependencies.keys).map((package) {
      var constraint = new VersionRange(
          min: lower[package],
          includeMin: true,
          max: upper[package],
          includeMax: false);

      _alreadyListedDependencies[package] = constraint.union(
          _alreadyListedDependencies[package] ?? VersionConstraint.empty);

      return new Incompatibility([
        new Term(_ref.withConstraint(constraint), true),
        new Term(dependencies[package], false)
      ], IncompatibilityCause.dependency);
    }).toList();
  }

  /// If the version at [index] in [_versions] isn't compatible with the current
  /// SDK version, returns an [Incompatibility] indicating that.
  ///
  /// Otherwise, returns `null`.
  Future<Incompatibility> _checkSdkConstraint(int index,
      {bool flutter: false}) async {
    var versions = await _versions;

    bool allowsSdk(Pubspec pubspec) => flutter
        ? _matchesFlutterSdkConstraint(pubspec)
        : _matchesDartSdkConstraint(pubspec);

    if (allowsSdk(await _source.describe(versions[index]))) return null;

    var bounds = await _findBounds(index, (pubspec) => !allowsSdk(pubspec));
    var incompatibleVersions = new VersionRange(
        min: bounds.first == 0 ? null : versions[bounds.first].version,
        includeMin: true,
        max: bounds.last == versions.length - 1
            ? null
            : versions[bounds.last + 1].version,
        includeMax: false);
    _knownInvalidSdks = incompatibleVersions.union(_knownInvalidSdks);

    var sdkConstraint = await foldAsync(
        slice(versions, bounds.first, bounds.last + 1), VersionConstraint.empty,
        (previous, version) async {
      var pubspec = await _source.describe(version);
      return previous.union(
          flutter ? pubspec.flutterSdkConstraint : pubspec.dartSdkConstraint);
    });

    return new Incompatibility(
        [new Term(_ref.withConstraint(incompatibleVersions), true)],
        new SdkCause(sdkConstraint, flutter: flutter));
  }

  /// Returns the first and last indices in [_versions] of the contiguous set of
  /// versions whose pubspecs match [match].
  ///
  /// Assumes [match] returns true for the pubspec whose version is at [index].
  Future<Pair<int, int>> _findBounds(
      int start, bool match(Pubspec pubspec)) async {
    var versions = await _versions;

    var first = start - 1;
    while (first > 0) {
      if (!match(await _source.describe(versions[first]))) break;
      first--;
    }

    var last = start + 1;
    while (last < versions.length) {
      if (!match(await _source.describe(versions[last]))) break;
      last++;
    }

    return new Pair(first + 1, last - 1);
  }

  /// Returns a map where each key is a package name and each value is the upper
  /// or lower (according to [upper]) bound of the range of versions with an
  /// identical dependency to that in [dependencies], around the version at
  /// [index].
  ///
  /// If a package is absent from the return value, that indicates indicate that
  /// all versions above or below [index] (according to [upper]) have the same
  /// dependency.
  Future<Map<String, Version>> _dependencyBounds(
      Map<String, PackageRange> dependencies, int index,
      {bool upper: true}) async {
    var versions = await _versions;
    var bounds = <String, Version>{};
    var previous = versions[index];
    for (var id in upper
        ? versions.skip(index + 1)
        : versions.reversed.skip(versions.length - index)) {
      var pubspec = await _source.describe(id);

      // The upper bound is exclusive and so is the first package with a
      // different dependency. The lower bound is inclusive, and so is the last
      // package with the same dependency.
      var boundary = (upper ? id : previous).version;

      // Once we hit an incompatible version, it doesn't matter whether it has
      // the same dependencies.
      if (!_matchesDartSdkConstraint(pubspec) ||
          !_matchesFlutterSdkConstraint(pubspec)) {
        for (var name in dependencies.keys) {
          bounds.putIfAbsent(name, () => boundary);
        }
        break;
      }

      for (var range in dependencies.values) {
        if (bounds.containsKey(range.name)) continue;
        if (pubspec.dependencies[range.name] != range) {
          bounds[range.name] = boundary;
        }
      }

      if (bounds.length == dependencies.length) break;
      previous = id;
    }

    return bounds;
  }

  /// Returns whether [pubspec]'s Dart SDK constraint matches the current Dart
  /// SDK version.
  bool _matchesDartSdkConstraint(Pubspec pubspec) =>
      _overriddenPackages.contains(pubspec.name) ||
      pubspec.dartSdkConstraint.allows(sdk.version);

  /// Returns whether [pubspec]'s Flutter SDK constraint matches the current Flutter
  /// SDK version.
  bool _matchesFlutterSdkConstraint(Pubspec pubspec) =>
      pubspec.flutterSdkConstraint == null ||
      _overriddenPackages.contains(pubspec.name) ||
      (flutter.isAvailable &&
          pubspec.flutterSdkConstraint.allows(flutter.version));
}

/// A fake source that contains only the root package.
///
/// This only implements the subset of the [BoundSource] API that
/// [PackageLister] uses to find information about packages.
class _RootSource extends BoundSource {
  /// An error to throw for unused source methods.
  UnsupportedError get _unsupported =>
      new UnsupportedError("_RootSource is not a full source.");

  /// The entrypoint package.
  final Package _package;

  _RootSource(this._package);

  Future<List<PackageId>> getVersions(PackageRef ref) {
    assert(ref.isRoot);
    return new Future.value([new PackageId.root(_package)]);
  }

  Future<Pubspec> describe(PackageId id) {
    assert(id.isRoot);
    return new Future.value(_package.pubspec);
  }

  Source get source => throw _unsupported;
  SystemCache get systemCache => throw _unsupported;
  Future<List<PackageId>> doGetVersions(PackageRef ref) => throw _unsupported;
  Future<Pubspec> doDescribe(PackageId id) => throw _unsupported;
  Future get(PackageId id, String symlink) => throw _unsupported;
  String getDirectory(PackageId id) => throw _unsupported;
}
