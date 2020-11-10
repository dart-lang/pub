// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:meta/meta.dart';
import 'package:pub_semver/pub_semver.dart';

import 'package_name.dart';
import 'pubspec.dart';
import 'source/hosted.dart';
import 'system_cache.dart';

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

Future<Pubspec> constrainedToAtLeastNullSafetyPubspec(
    Pubspec original, SystemCache cache) async {
  /// Get the first version of [package] opting in to null-safety.
  Future<VersionRange> constrainToFirstWithNullSafety(
      PackageRange packageRange) async {
    final ref = packageRange.toRef();
    final available = await cache.source(ref.source).getVersions(ref);
    if (available.isEmpty) {
      return stripUpperBound(packageRange.constraint);
    }

    available.sort((x, y) => x.version.compareTo(y.version));

    for (final p in available) {
      final pubspec = await cache.source(ref.source).describe(p);
      if (pubspec.languageVersion.supportsNullSafety) {
        return VersionRange(min: p.version, includeMin: true);
      }
    }
    return stripUpperBound(packageRange.constraint);
  }

  Future<List<PackageRange>> allConstrainedToAtLeastNullSafety(
    Map<String, PackageRange> constrained,
  ) async {
    final result = await Future.wait(constrained.keys.map((name) async {
      final packageRange = constrained[name];
      var unconstrainedRange = packageRange;

      /// We only need to remove the upper bound if it is a hosted package.
      if (packageRange.source is HostedSource) {
        unconstrainedRange = PackageRange(
            packageRange.name,
            packageRange.source,
            await constrainToFirstWithNullSafety(packageRange),
            packageRange.description,
            features: packageRange.features);
      }
      return unconstrainedRange;
    }));

    return result;
  }

  final constrainedLists = await Future.wait([
    allConstrainedToAtLeastNullSafety(original.dependencies),
    allConstrainedToAtLeastNullSafety(original.devDependencies),
  ]);

  return Pubspec(
    original.name,
    version: original.version,
    sdkConstraints: original.sdkConstraints,
    dependencies: constrainedLists[0],
    devDependencies: constrainedLists[1],
    dependencyOverrides: original.dependencyOverrides.values,
  );
}

/// Returns new pubspec with the same dependencies as [original] but with the
/// upper bounds of the constraints removed.
///
/// If [stripOnly] is provided, only the packages whose names are in
/// [stripOnly] will have their upper bounds removed. If [stripOnly] is
/// not specified or empty, then all packages will have their upper bounds
/// removed.
Pubspec stripVersionUpperBounds(Pubspec original,
    {Iterable<String> stripOnly}) {
  ArgumentError.checkNotNull(original, 'original');
  stripOnly ??= [];

  List<PackageRange> _stripUpperBounds(
    Map<String, PackageRange> constrained,
  ) {
    final result = <PackageRange>[];

    for (final name in constrained.keys) {
      final packageRange = constrained[name];
      var unconstrainedRange = packageRange;

      /// We only need to remove the upper bound if it is a hosted package.
      if (packageRange.source is HostedSource &&
          (stripOnly.isEmpty || stripOnly.contains(packageRange.name))) {
        unconstrainedRange = PackageRange(
            packageRange.name,
            packageRange.source,
            stripUpperBound(packageRange.constraint),
            packageRange.description,
            features: packageRange.features);
      }
      result.add(unconstrainedRange);
    }

    return result;
  }

  return Pubspec(
    original.name,
    version: original.version,
    sdkConstraints: original.sdkConstraints,
    dependencies: _stripUpperBounds(original.dependencies),
    devDependencies: _stripUpperBounds(original.devDependencies),
    dependencyOverrides: original.dependencyOverrides.values,
  );
}

/// Removes the upper bound of [constraint]. If [constraint] is the
/// empty version constraint, [VersionConstraint.empty] will be returned.
@visibleForTesting
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
