// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

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
Incompatibility reformatRanges(Map<PackageRef, PackageLister> packageListers,
    Incompatibility incompatibility) {
  var cause = incompatibility.cause;
  if (cause is ConflictCause) {
    var conflict = cause as ConflictCause;
    cause = ConflictCause(reformatRanges(packageListers, conflict.conflict),
        reformatRanges(packageListers, conflict.other));
  }

  return Incompatibility(
      incompatibility.terms
          .map((term) => _reformatTerm(packageListers, term))
          .toList(),
      _reformatCause(packageListers, cause));
}

/// Returns [term] with the upper and lower bounds of its package range
/// reformatted if necessary.
Term _reformatTerm(Map<PackageRef, PackageLister> packageListers, Term term) {
  var versions = packageListers[term.package.toRef()]?.cachedVersions ?? [];

  if (term.package.constraint is! VersionRange) return term;
  if (term.package.constraint is Version) return term;
  var range = term.package.constraint as VersionRange;

  var min = _reformatMin(versions, range);
  var tuple = _reformatMax(versions, range);
  var max = tuple?.first;
  var includeMax = tuple?.last;

  if (min == null && max == null) return term;
  return Term(
      term.package
          .withConstraint(VersionRange(
              min: min ?? range.min,
              max: max ?? range.max,
              includeMin: range.includeMin,
              includeMax: includeMax ?? range.includeMax,
              alwaysIncludeMaxPreRelease: true))
          .withTerseConstraint(),
      term.isPositive);
}

/// Returns the new minimum version to use for [range], or `null` if it doesn't
/// need to be reformatted.
Version _reformatMin(List<PackageId> versions, VersionRange range) {
  if (range.min == null) return null;
  if (!range.includeMin) return null;
  if (!range.min.isFirstPreRelease) return null;

  var index = _lowerBound(versions, range.min);
  var next = index == versions.length ? null : versions[index].version;

  // If there's a real pre-release version of [range.min], use that as the min.
  // Otherwise, use the release version.
  return next != null && equalsIgnoringPreRelease(range.min, next)
      ? next
      : Version(range.min.major, range.min.minor, range.min.patch);
}

/// Returns the new maximum version to use for [range] and whether that maximum
/// is inclusive, or `null` if it doesn't need to be reformatted.
Pair<Version, bool> _reformatMax(List<PackageId> versions, VersionRange range) {
  if (range.max == null) return null;
  if (range.includeMax) return null;
  if (range.max.isPreRelease) return null;
  if (range.min != null &&
      range.min.isPreRelease &&
      equalsIgnoringPreRelease(range.min, range.max)) {
    return null;
  }

  var index = _lowerBound(versions, range.max);
  var previous = index == 0 ? null : versions[index - 1].version;

  return previous != null && equalsIgnoringPreRelease(previous, range.max)
      ? Pair(previous, true)
      : Pair(range.max.firstPreRelease, false);
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
    var mid = min + ((max - min) >> 1);
    var id = ids[mid];
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
        IncompatibilityCause cause) =>
    cause is ConflictCause
        ? ConflictCause(reformatRanges(packageListers, cause.conflict),
            reformatRanges(packageListers, cause.other))
        : cause;
