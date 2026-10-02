// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:pub_semver/pub_semver.dart';

import '../package_name.dart';
import '../utils.dart';
import 'incompatibility.dart';
import 'incompatibility_cause.dart';
import 'package_lister.dart';
import 'term.dart';

/// Replaces version ranges in [incompatibility] and its causes with more
/// human-readable (but less technically-accurate) ranges.
///
/// We use a lot of ranges in the solver that explicitly allow pre-release
// ignore: unintended_html_in_doc_comment https://github.com/dart-lang/linter/issues/5055
/// versions, such as `>=1.0.0-0 <2.0.0` or `>=1.0.0 <2.0.0-∞`. These ensure
/// that adjacent ranges can be merged together, which makes the solver's job
/// much easier. However, they're not super human-friendly, and in practice most
/// package versions don't actually have pre-releases available.
///
/// This replaces lower bounds like `>=1.0.0-0` with the first version that
/// actually exists for a package, and upper bounds like `<2.0.0-∞` either with
/// the release version (`<2.0.0`) if no pre-releases exist or with an inclusive
/// bound on the last pre-release version that actually exists
/// (`<=2.0.0-dev.1`).
Incompatibility reformatRanges(
  Map<PackageRef, PackageLister> packageListers,
  Incompatibility incompatibility,
) {
  final cause = incompatibility.cause;
  if (cause is ConflictCause) {
    final simplified = _trySimplifySingleVersionConflict(
      packageListers,
      incompatibility,
      cause.conflict,
      cause.other,
    );
    if (simplified != null) {
      return reformatRanges(packageListers, simplified);
    }
  }

  return Incompatibility(
    incompatibility.terms
        .map((term) => _reformatTerm(packageListers, term))
        .toList(),
    _reformatCause(packageListers, cause),
  );
}

/// If [incompatibility] was derived by resolving a
/// [NoVersionsIncompatibilityCause] with a derivation from a single-version
/// incompatibility (emitted for a locked version before all versions were
/// listed), collapses the no-versions step by widening the single-version
/// package range to the combined range.
Incompatibility? _trySimplifySingleVersionConflict(
  Map<PackageRef, PackageLister> packageListers,
  Incompatibility incompatibility,
  Incompatibility conflict,
  Incompatibility other,
) {
  final (noVersions, otherBranch) = switch ((conflict.cause, other.cause)) {
    (NoVersionsIncompatibilityCause(), _) => (conflict, other),
    (_, NoVersionsIncompatibilityCause()) => (other, conflict),
    _ => (null, null),
  };
  if (noVersions == null || otherBranch == null) return null;

  final ref = noVersions.terms.single.package.toRef();
  final singleTerm = otherBranch.terms.firstWhereOrNull(
    (term) =>
        term.isPositive &&
        term.package.toRef() == ref &&
        term.constraint is Version,
  );
  if (singleTerm == null) return null;

  final generalizedTerm = incompatibility.terms.firstWhereOrNull(
    (term) => term.isPositive && term.package.toRef() == ref,
  );
  if (generalizedTerm == null) return null;

  // Only collapse if the locked version is among the package's listed versions
  // (otherwise it truly is a distinct unlisted version).
  final versions = packageListers[ref]?.cachedVersions;
  if (versions == null ||
      !versions.any((id) => id.version == singleTerm.constraint)) {
    return null;
  }

  return _widenPackage(
    otherBranch,
    singleTerm.package,
    generalizedTerm.package,
  );
}

/// Replaces positive occurrences of [singleVersion] with [generalized] in
/// [incompatibility] and its causes.
Incompatibility _widenPackage(
  Incompatibility incompatibility,
  PackageRange singleVersion,
  PackageRange generalized,
) {
  final terms = [
    for (final term in incompatibility.terms)
      if (term.isPositive && term.package == singleVersion)
        Term(generalized, true)
      else
        term,
  ];
  final cause = switch (incompatibility.cause) {
    ConflictCause(:final conflict, :final other) => ConflictCause(
      _widenPackage(conflict, singleVersion, generalized),
      _widenPackage(other, singleVersion, generalized),
    ),
    DependencyIncompatibilityCause(:final depender, :final target)
        when depender == singleVersion =>
      DependencyIncompatibilityCause(generalized, target),
    final cause => cause,
  };
  return Incompatibility(terms, cause);
}

/// Returns [term] with the upper and lower bounds of its package range
/// reformatted if necessary.
Term _reformatTerm(Map<PackageRef, PackageLister> packageListers, Term term) {
  final versions = packageListers[term.package.toRef()]?.cachedVersions ?? [];

  if (term.package.constraint is! VersionRange) return term;
  if (term.package.constraint is Version) return term;
  final range = term.package.constraint as VersionRange;

  final min = _reformatMin(versions, range);
  final maxInfo = reformatMax(versions, range);

  if (min == null && maxInfo == null) {
    return Term(term.package.withTerseConstraint(), term.isPositive);
  }

  final (max, includeMax) = maxInfo ?? (range.max, range.includeMax);

  return Term(
    term.package
        .toRef()
        .withConstraint(
          VersionRange(
            min: min ?? range.min,
            max: max,
            includeMin: range.includeMin,
            includeMax: includeMax,
            alwaysIncludeMaxPreRelease: true,
          ),
        )
        .withTerseConstraint(),
    term.isPositive,
  );
}

/// Returns the new minimum version to use for [range], or `null` if it doesn't
/// need to be reformatted.
Version? _reformatMin(List<PackageId> versions, VersionRange range) {
  final min = range.min;
  if (min == null) return null;
  if (!range.includeMin) return null;
  if (!min.isFirstPreRelease) return null;

  final index = _lowerBound(versions, min);
  final next = index == versions.length ? null : versions[index].version;

  // If there's a real pre-release version of [range.min], use that as the min.
  // Otherwise, use the release version.
  return next != null && equalsIgnoringPreRelease(min, next)
      ? next
      : Version(min.major, min.minor, min.patch);
}

/// Returns the new maximum version to use for [range] and whether that maximum
/// is inclusive, or `null` if it doesn't need to be reformatted.
@visibleForTesting
(Version maxVersion, bool inclusive)? reformatMax(
  List<PackageId> versions,
  VersionRange range,
) {
  // This corresponds to the logic in the constructor of [VersionRange] with
  // `alwaysIncludeMaxPreRelease = false` for discovering when a max-bound
  // should not include prereleases.

  final max = range.max;
  final min = range.min;
  if (max == null) return null;
  if (range.includeMax) return null;
  if (max.isPreRelease) return null;
  if (max.build.isNotEmpty) return null;
  if (min != null && min.isPreRelease && equalsIgnoringPreRelease(min, max)) {
    return null;
  }

  final index = _lowerBound(versions, max);
  final previous = index == 0 ? null : versions[index - 1].version;

  return previous != null && equalsIgnoringPreRelease(previous, max)
      ? (previous, true)
      : (max.firstPreRelease, false);
}

/// Returns the first index in [ids] (which is sorted by version) whose version
/// is greater than or equal to [version].
///
/// Returns `ids.length` if all the versions in `ids` are less than [version].
///
/// We can't use the `collection` package's `lowerBound()` function here because
/// [version] isn't the same as [ids]' element type.
int _lowerBound(List<PackageId> ids, Version version) {
  var min = 0;
  var max = ids.length;
  while (min < max) {
    final mid = min + ((max - min) >> 1);
    final id = ids[mid];
    if (id.version.compareTo(version) < 0) {
      min = mid + 1;
    } else {
      max = mid;
    }
  }
  return min;
}

/// If [cause] is a [ConflictCause], returns a copy of it with the
/// incompatibilities reformatted.
///
/// Otherwise, returns it as-is.
IncompatibilityCause _reformatCause(
  Map<PackageRef, PackageLister> packageListers,
  IncompatibilityCause cause,
) =>
    cause is ConflictCause
        ? ConflictCause(
          reformatRanges(packageListers, cause.conflict),
          reformatRanges(packageListers, cause.other),
        )
        : cause;
