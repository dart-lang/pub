// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub_semver/pub_semver.dart';

import '../exceptions.dart';
import '../sdk.dart';
import 'incompatibility.dart';

/// The reason an [Incompatibility]'s terms are incompatible.
abstract class IncompatibilityCause {
  /// The incompatibility represents the requirement that the root package
  /// exists.
  static const IncompatibilityCause root = _Cause('root');

  /// The incompatibility represents a package's dependency.
  static const IncompatibilityCause dependency = _Cause('dependency');

  /// The incompatibility represents the user's request that we use the latest
  /// version of a given package.
  static const IncompatibilityCause useLatest = _Cause('use latest');

  /// The incompatibility indicates that the package has no versions that match
  /// the given constraint.
  static const IncompatibilityCause noVersions = _Cause('no versions');

  /// The incompatibility indicates that the package has an unknown source.
  static const IncompatibilityCause unknownSource = _Cause('unknown source');
}

/// The incompatibility was derived from two existing incompatibilities during
/// conflict resolution.
class ConflictCause implements IncompatibilityCause {
  /// The incompatibility that was originally found to be in conflict, from
  /// which the target incompatibility was derived.
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

  @override
  String toString() => _name;
}

/// The incompatibility represents a package's SDK constraint being
/// incompatible with the current SDK.
class SdkCause implements IncompatibilityCause {
  /// The union of all the incompatible versions' constraints on the SDK.
  final VersionConstraint constraint;

  /// The SDK with which the package was incompatible.
  final Sdk sdk;

  SdkCause(this.constraint, this.sdk);
}

/// The incompatibility represents a package that couldn't be found by its
/// source.
class PackageNotFoundCause implements IncompatibilityCause {
  /// The exception indicating why the package couldn't be found.
  final PackageNotFoundException exception;

  /// If the incompatibility was caused by an SDK being unavailable, this is
  /// that SDK.
  ///
  /// Otherwise `null`.
  Sdk get sdk => exception.missingSdk;

  PackageNotFoundCause(this.exception);
}
