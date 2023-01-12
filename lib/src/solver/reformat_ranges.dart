// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

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
) =>
    Incompatibility(
      incompatibility.terms
          .map((term) => _reformatTerm(packageListers, term))
          .toList(),
      _reformatCause(packageListers, incompatibility.cause),
    );

/// Returns [term] with the upper and lower bounds of its package range
/// reformatted if necessary.
Term _reformatTerm(Map<PackageRef, PackageLister> packageListers, Term term) {
  var versions = packageListers[term.package.toRef()]?.cachedVersions ?? [];

  if (term.package.constraint is! VersionRange) return term;
  if (term.package.constraint is Version) return term;
  var range = term.package.constraint as VersionRange;

  var min = _reformatMin(versions, range);
  var tuple = reformatMax(versions, range);
  var max = tuple?.first;
  var includeMax = tuple?.last;

  if (min == null && max == null) return term;
  return Term(
    term.package
        .toRef()
        .withConstraint(
          VersionRange(
            min: min ?? range.min,
            max: max ?? range.max,
            includeMin: range.includeMin,
            includeMax: includeMax ?? range.includeMax,
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
  var min = range.min;
  if (min == null) return null;
  if (!range.includeMin) return null;
  if (!min.isFirstPreRelease) return null;

  var index = _lowerBound(versions, min);
  var next = index == versions.length ? null : versions[index].version;

  // If there's a real pre-release version of [range.min], use that as the min.
  // Otherwise, use the release version.
  return next != null && equalsIgnoringPreRelease(min, next)
      ? next
      : Version(min.major, min.minor, min.patch);
}

/// Returns the new maximum version to use for [range] and whether that maximum
/// is inclusive, or `null` if it doesn't need to be reformatted.
@visibleForTesting
Pair<Version, bool>? reformatMax(List<PackageId> versions, VersionRange range) {
  // This corresponds to the logic in the constructor of [VersionRange] with
  // `alwaysIncludeMaxPreRelease = false` for discovering when a max-bound
  // should not include prereleases.

  var max = range.max;
  var min = range.min;
  if (max == null) return null;
  if (range.includeMax) return null;
  if (max.isPreRelease) return null;
  if (max.build.isNotEmpty) return null;
  if (min != null && min.isPreRelease && equalsIgnoringPreRelease(min, max)) {
    return null;
  }

  var index = _lowerBound(versions, max);
  var previous = index == 0 ? null : versions[index - 1].version;

  return previous != null && equalsIgnoringPreRelease(previous, max)
      ? Pair(previous, true)
      : Pair(max.firstPreRelease, false);
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
  IncompatibilityCause cause,
) =>
    cause is ConflictCause
        ? ConflictCause(
            reformatRanges(packageListers, cause.conflict),
            reformatRanges(packageListers, cause.other),
          )
        : cause;
