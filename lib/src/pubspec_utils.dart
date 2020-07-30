// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package_name.dart';
import 'pubspec.dart';
import 'source/hosted.dart';
import 'utils.dart';

/// Returns a new [Pubspec] without [original]'s dev_dependencies.
Pubspec stripDevDependencies(Pubspec original) {
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
/// upper bounds of the constraints removed.
///
/// If [upgradeOnly] is provided, only the packages whose names are in
/// [upgradeOnly] will have their upper bounds removed.
Pubspec stripVersionConstraints(Pubspec original, {List<String> upgradeOnly}) {
  upgradeOnly ??= [];

  List<PackageRange> _unconstrained(
    Map<String, PackageRange> constrained,
  ) {
    final result = <PackageRange>[];

    for (final name in constrained.keys) {
      final packageRange = constrained[name];
      var unconstrainedRange = packageRange;
      if (packageRange.source is HostedSource &&
          (upgradeOnly.isEmpty || upgradeOnly.contains(packageRange.name))) {
        unconstrainedRange = PackageRange(
            packageRange.name,
            packageRange.source,
            removeUpperBound(packageRange.constraint),
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
    dependencies: _unconstrained(original.dependencies),
    devDependencies: _unconstrained(original.devDependencies),
    dependencyOverrides: original.dependencyOverrides.values,
  );
}
