// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:async/async.dart';
import 'package:pub_semver/pub_semver.dart';

import '../flutter.dart' as flutter;
import '../package_name.dart';
import '../pubspec.dart';
import '../source.dart';
import '../sdk.dart' as sdk;
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

  PackageLister(SystemCache cache, this._ref, this._locked)
      : _source = cache.source(_ref.source);

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
    var min = constraint is VersionRange ? constraint.min : null;

    // Return the most preferable version that matches [constraint]: the latest
    // non-prerelease version if one exists, or the latest prerelease version
    // otherwise.
    PackageId bestPrerelease;
    for (var id in versions.reversed) {
      // If [constraint] has a minimum, we can bail early once we're past it.
      if (min != null && id.version < min) break;

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
    if (_versionsCache == null && id.version == _locked.version) {
      if (_listedLockedVersion) return const [];
      _listedLockedVersion = true;
      if (!_matchesSdkConstraint(pubspec)) {
        return [
          new Incompatibility([new Term(id, true)], IncompatibilityCause.sdk)
        ];
      } else {
        return pubspec.dependencies.values
            .map((range) => new Incompatibility(
                [new Term(id, true), new Term(range, false)],
                IncompatibilityCause.dependency))
            .toList();
      }
    }

    var versions = await _versions;
    var index = indexWhere(versions, (other) => identical(id, other));

    if (!_matchesSdkConstraint(pubspec)) {
      var lower = await _unmatchedSdkBound(index, upper: false);
      var upper = await _unmatchedSdkBound(index, upper: true);
      var constraint = new VersionRange(
          min: lower, includeMin: true, max: upper, includeMax: true);
      _knownInvalidSdks = constraint.union(_knownInvalidSdks);

      return [
        new Incompatibility([new Term(_ref.withConstraint(constraint), true)],
            IncompatibilityCause.sdk)
      ];
    }

    // Don't recompute dependencies that have already been emitted.
    var dependencies = new Map.from(pubspec.dependencies);
    for (var package in dependencies.keys.toList()) {
      var constraint = _alreadyListedDependencies[package];
      if (constraint != null && constraint.allows(id.version)) {
        dependencies.remove(package);
      }
    }

    var lower = await _dependencyBounds(dependencies, index, upper: false);
    var upper = await _dependencyBounds(dependencies, index, upper: true);

    return ordered(pubspec.dependencies.keys).map((package) {
      var constraint = new VersionRange(
          min: lower[package],
          includeMin: true,
          max: upper[package],
          includeMax: false);

      _alreadyListedDependencies[package] = constraint.union(
          _alreadyListedDependencies[package] ?? VersionConstraint.empty);

      return new Incompatibility([
        new Term(_ref.withConstraint(constraint), true),
        new Term(pubspec.dependencies[package], false)
      ], IncompatibilityCause.dependency);
    }).toList();
  }

  /// Returns a version bound indicating where in [_versions] this package
  /// stopped having an incompatible SDK constraint.
  ///
  /// If [inclusive] is `true`, this returns the last version in [_versions]
  /// with an incompatible SDK constraint. If it's `false`, it returns the first
  /// version in [_versions] with a compatible SDK constraint.
  ///
  /// This may return `null`, indicating that all [_versions] have an
  /// incompatible SDK constraint.
  Future<Version> _unmatchedSdkBound(int index, {bool upper: true}) async {
    var versions = await _versions;
    var previous = versions[index];
    for (var id in upper
        ? versions.skip(index + 1)
        : versions.reversed.skip(versions.length - index)) {
      var pubspec = await _source.describe(id);
      if (_matchesSdkConstraint(pubspec)) {
        return (upper ? id : previous).version;
      }
      previous = id;
    }

    return null;
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
      if (!_matchesSdkConstraint(pubspec)) {
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

  /// Returns whether [pubspec]'s SDK constraint matches the current SDK
  /// version.
  bool _matchesSdkConstraint(Pubspec pubspec) {
    if (!pubspec.dartSdkConstraint.allows(sdk.version)) {
      return false;
    }
    if (pubspec.flutterSdkConstraint != null) {
      if (!flutter.isAvailable) return false;
      if (!pubspec.flutterSdkConstraint.allows(flutter.version)) return false;
    }
    return true;
  }
}
