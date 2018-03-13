// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub_semver/pub_semver.dart';

import 'incompatibility.dart';

/// The reason an [Incompatibility]'s terms are incompatible.
abstract class IncompatibilityCause {
  /// The incompatibility represents the requirement that the root package
  /// exists.
  static const IncompatibilityCause root = const _Cause("root");

  /// The incompatibility represents a package's dependency.
  static const IncompatibilityCause dependency = const _Cause("dependency");

  /// The incompatibility indicates that the package has no versions that match
  /// the given constraint.
  static const IncompatibilityCause noVersions = const _Cause("no versions");

  /// The incompatibility indicates that the package has an unknown source.
  static const IncompatibilityCause unknownSource =
      const _Cause("unknown source");
}

/// The incompatibility was derived from two existing incompatibilities during
/// conflict resolution.
class ConflictCause implements IncompatibilityCause {
  /// The incompatibility that was originally found to be in conflict, from
  /// which the target incompatiblity was derived.
  final Incompatibility conflict;

  /// The incompatibility that caused the most recent satisfier for [conflict],
  /// from which the target incompatibility was derived.
  final Incompatibility other;

  ConflictCause(this.conflict, this.other);
}

/// A class for stateless [IncompatibilityCause]s.
class _Cause implements IncompatibilityCause {
  final String _name;

  const _Cause(this._name);

  String toString() => _name;
}

/// The incompatibility represents a package's SDK constraint being
/// incompatible with the current SDK.
class SdkCause implements IncompatibilityCause {
  /// The union of all the incompatible versions' constraints on the SDK.
  final VersionConstraint constraint;

  /// Whether this is a constraint on the Flutter SDK (as opposed to the main
  /// Dart SDK).
  final bool isFlutter;

  SdkCause(this.constraint, {bool flutter: false}) : isFlutter = flutter;
}
