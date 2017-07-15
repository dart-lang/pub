// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:collection';

import 'package:collection/collection.dart';
import 'package:pub_semver/pub_semver.dart';

import 'package_name.dart';

/// A feature declared by a package.
///
/// Features are collections of optional dependencies. Dependers can choose
/// which features to require from packages they depend on.
class Feature {
  /// The name of this feature.
  final String name;

  /// Whether this feature is enabled by default.
  final bool onByDefault;

  /// The additional dependencies added by this feature.
  final List<PackageRange> dependencies;

  /// Other features that this feature requires.
  final List<String> requires;

  /// This feature's constraint on the Dart SDK, or [VersionConstraint.any] if
  /// none is specified.
  final VersionConstraint dartSdkConstraint;

  /// This feature's constraint on the Flutter SDK, or `null` if none is
  /// specified.
  final VersionConstraint flutterSdkConstraint;

  /// Returns the set of features in [features] that are enabled by
  /// [dependencies].
  static Set<Feature> featuresEnabledBy(Map<String, Feature> features,
      Map<String, FeatureDependency> dependencies) {
    if (features.isEmpty) return const UnmodifiableSetView.empty();

    // [enableFeature] adds a feature to [features], along with any other
    // features it requires.
    var enabledFeatures = new Set<Feature>();
    enableFeature(Feature feature) {
      if (!enabledFeatures.add(feature)) return;
      for (var require in feature.requires) {
        enableFeature(features[require]);
      }
    }

    // Enable all features that are explicitly enabled by dependencies, or on by
    // default and not disabled by dependencies.
    for (var feature in features.values) {
      if (dependencies[feature.name]?.isEnabled ?? feature.onByDefault) {
        enableFeature(feature);
      }
    }

    return enabledFeatures;
  }

  Feature(this.name, Iterable<PackageRange> dependencies,
      {Iterable<String> requires,
      VersionConstraint dartSdkConstraint,
      this.flutterSdkConstraint,
      this.onByDefault: true})
      : dependencies = new UnmodifiableListView(dependencies.toList()),
        requires = requires == null
            ? const []
            : new UnmodifiableListView(requires.toList()),
        dartSdkConstraint = dartSdkConstraint ?? VersionConstraint.any;

  String toString() => name;
}
