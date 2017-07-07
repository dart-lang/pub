// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:collection';

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

  /// This feature's constraint on the Dart SDK, or [VersionConstraint.any] if
  /// none is specified.
  final VersionConstraint dartSdkConstraint;

  /// This feature's constraint on the Flutter SDK, or `null` if none is
  /// specified.
  final VersionConstraint flutterSdkConstraint;

  Feature(this.name, Iterable<PackageRange> dependencies,
      {VersionConstraint dartSdkConstraint,
      this.flutterSdkConstraint,
      this.onByDefault: true})
      : dependencies = new UnmodifiableListView(dependencies.toList()),
        dartSdkConstraint = dartSdkConstraint ?? VersionConstraint.any;

  /// Returns whether this feature should be enabled, given both [onByDefault]
  /// and a [features] map that may override it.
  bool isEnabled(Map<String, bool> features) => features[name] ?? onByDefault;

  String toString() => name;
}
