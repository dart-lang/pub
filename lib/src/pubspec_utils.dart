// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub_semver/pub_semver.dart';

import 'package_name.dart';
import 'pubspec.dart';

/// Returns a new [Pubspec] without [original]'s dev_dependencies.
Pubspec stripDevDependencies(Pubspec original) {
  ArgumentError.checkNotNull(original, 'original');

  return Pubspec(
    original.name,
    version: original.version,
    sdkConstraints: original.sdkConstraints,
    dependencies: original.dependencies.values,
    devDependencies: [], // explicitly give empty list, to prevent lazy parsing
    dependencyOverrides: original.dependencyOverrides.values,
  );
}

/// Returns a new [Pubspec] without [original]'s dependency_overrides.
Pubspec stripDependencyOverrides(Pubspec original) {
  ArgumentError.checkNotNull(original, 'original');

  return Pubspec(
    original.name,
    version: original.version,
    sdkConstraints: original.sdkConstraints,
    dependencies: original.dependencies.values,
    devDependencies: original.devDependencies.values,
    dependencyOverrides: [],
  );
}

/// Returns new pubspec with the same dependencies as [original] but with the
/// the bounds of the constraints removed.
///
/// If [stripLower] is `false` (the default) only the upper bound is removed.
///
/// If [stripOnly] is provided, only the packages whose names are in [stripOnly]
/// will have their bounds removed. If [stripOnly] is not specified or empty,
/// then all packages will have their bounds removed.
Pubspec stripVersionBounds(
  Pubspec original, {
  Iterable<String>? stripOnly,
  bool stripLowerBound = false,
}) {
  ArgumentError.checkNotNull(original, 'original');
  stripOnly ??= [];

  List<PackageRange> stripBounds(
    Map<String, PackageRange> constrained,
  ) {
    final result = <PackageRange>[];

    for (final name in constrained.keys) {
      final packageRange = constrained[name]!;
      var unconstrainedRange = packageRange;

      if (stripOnly!.isEmpty || stripOnly.contains(packageRange.name)) {
        unconstrainedRange = PackageRange(
          packageRange.toRef(),
          stripLowerBound
              ? VersionConstraint.any
              : stripUpperBound(packageRange.constraint),
        );
      }
      result.add(unconstrainedRange);
    }

    return result;
  }

  return Pubspec(
    original.name,
    version: original.version,
    sdkConstraints: original.sdkConstraints,
    dependencies: stripBounds(original.dependencies),
    devDependencies: stripBounds(original.devDependencies),
    dependencyOverrides: original.dependencyOverrides.values,
  );
}

/// Removes the upper bound of [constraint]. If [constraint] is the
/// empty version constraint, [VersionConstraint.empty] will be returned.
VersionConstraint stripUpperBound(VersionConstraint constraint) {
  ArgumentError.checkNotNull(constraint, 'constraint');

  /// A [VersionConstraint] has to either be a [VersionRange], [VersionUnion],
  /// or the empty [VersionConstraint].
  if (constraint is VersionRange) {
    return VersionRange(min: constraint.min, includeMin: constraint.includeMin);
  }

  if (constraint is VersionUnion) {
    if (constraint.ranges.isEmpty) return VersionConstraint.empty;

    final firstRange = constraint.ranges.first;
    return VersionRange(min: firstRange.min, includeMin: firstRange.includeMin);
  }

  assert(constraint == VersionConstraint.empty, 'unknown constraint type');

  /// If it gets here, [constraint] is the empty version constraint, so we
  /// just return an empty version constraint.
  return VersionConstraint.empty;
}
