// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:collection/collection.dart';
import 'package:pub_semver/pub_semver.dart';

import 'entrypoint.dart';
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

/// Returns a pubspec with the same dependencies as [original] but with all
/// version constraints replaced by `>=c` where `c`, is the member of `current`
/// that has same name as the dependency.
Pubspec atLeastCurrent(Pubspec original, List<PackageId> current) {
  List<PackageRange> fixBounds(
    Map<String, PackageRange> constrained,
  ) {
    final result = <PackageRange>[];

    for (final name in constrained.keys) {
      final packageRange = constrained[name]!;
      final currentVersion = current.firstWhereOrNull((id) => id.name == name);
      if (currentVersion == null) {
        result.add(packageRange);
      } else {
        result.add(
          packageRange.toRef().withConstraint(
                VersionRange(min: currentVersion.version, includeMin: true),
              ),
        );
      }
    }

    return result;
  }

  return Pubspec(
    original.name,
    version: original.version,
    sdkConstraints: original.sdkConstraints,
    dependencies: fixBounds(original.dependencies),
    devDependencies: fixBounds(original.devDependencies),
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

/// Returns a somewhat normalized version the description of a dependency with a
/// version constraint (what comes after the version name in a dependencies
/// section) as a json-style object.
///
/// Will use just the constraint for dependencies hosted at the default host.
///
/// Relative paths will be relative to [relativeEntrypoint].
///
/// The syntax used for hosted will depend on the language version of
/// [relativeEntrypoint]
Object? pubspecDescription(
  PackageRange range,
  SystemCache cache,
  Entrypoint relativeEntrypoint,
) {
  final description = range.description;

  final constraint = range.constraint;
  if (description is HostedDescription &&
      description.url == cache.hosted.defaultUrl) {
    return constraint.toString();
  } else {
    return {
      range.source.name: description.serializeForPubspec(
        containingDir: relativeEntrypoint.rootDir,
        languageVersion: relativeEntrypoint.root.pubspec.languageVersion,
      ),
      if (!constraint.isAny) 'version': constraint.toString(),
    };
  }
}
