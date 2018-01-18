// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'incompatibility.dart';

/// The reason an [Incompatibility]'s terms are incompatible.
abstract class IncompatibilityCause {
  /// The incompatibility represents the requirement that the root package
  /// exists.
  static const IncompatibilityCause root = const _RootCause();

  /// The incompatibility represents a package's dependency.
  static const IncompatibilityCause dependency = const _DependencyCause();

  /// The incompatibility represents a package's SDK constraint being
  /// incompatible with the current SDK.
  static const IncompatibilityCause sdk = const _SdkCause();

  /// The incompatibility represents that the package has no versions that match
  /// the given constraint.
  static const IncompatibilityCause noVersions = const _NoVersionsCause();
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

class _RootCause implements IncompatibilityCause {
  const _RootCause();
}

class _DependencyCause implements IncompatibilityCause {
  const _DependencyCause();
}

class _NoVersionsCause implements IncompatibilityCause {
  const _NoVersionsCause();
}

// TODO(nweiz): Include more information about what SDK versions are allowed
// and/or whether Flutter is required but unavailable.
class _SdkCause implements IncompatibilityCause {
  const _SdkCause();
}
