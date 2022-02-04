// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub_semver/pub_semver.dart';

import '../exceptions.dart';
import '../sdk.dart';
import 'incompatibility.dart';

/// The reason an [Incompatibility]'s terms are incompatible.
abstract class IncompatibilityCause {
  const IncompatibilityCause._();

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

  /// Human readable notice / information providing context for this
  /// incompatibility.
  ///
  /// This may be multiple lines, and will be printed before the explanation.
  /// This is used highlight information that is useful for understanding the
  /// why this conflict happened.
  String? get notice => null;

  /// Human readable hint indicating how this incompatibility may be resolved.
  ///
  /// This may be multiple lines, and will be printed after the explanation.
  /// This should only be included if it is actionable and likely to resolve the
  /// issue for the user.
  String? get hint => null;
}

/// The incompatibility was derived from two existing incompatibilities during
/// conflict resolution.
class ConflictCause extends IncompatibilityCause {
  /// The incompatibility that was originally found to be in conflict, from
  /// which the target incompatibility was derived.
  final Incompatibility conflict;

  /// The incompatibility that caused the most recent satisfier for [conflict],
  /// from which the target incompatibility was derived.
  final Incompatibility other;

  ConflictCause(this.conflict, this.other) : super._();
}

/// A class for stateless [IncompatibilityCause]s.
class _Cause extends IncompatibilityCause {
  final String _name;

  const _Cause(this._name) : super._();

  @override
  String toString() => _name;
}

/// The incompatibility represents a package's SDK constraint being
/// incompatible with the current SDK.
class SdkCause extends IncompatibilityCause {
  /// The union of all the incompatible versions' constraints on the SDK.
  // TODO(zarah): Investigate if this can be non-nullable
  final VersionConstraint? constraint;

  /// The SDK with which the package was incompatible.
  final Sdk sdk;

  @override
  String? get notice {
    // If the SDK is not available, then we have an actionable [hint] printed
    // after the explanation. So we don't need to state that the SDK is not
    // available.
    if (!sdk.isAvailable) {
      return null;
    }
    // If the SDK is available and we have an incompatibility, then the user has
    // the wrong SDK version (one that is not compatible with any solution).
    // Thus, it makes sense to highlight the current SDK version.
    return 'The current ${sdk.name} SDK version is ${sdk.version}.';
  }

  @override
  String? get hint {
    // If the SDK is available, then installing it won't help
    if (sdk.isAvailable) {
      return null;
    }
    // Return an install message for the SDK, if there is an install message.
    return sdk.installMessage;
  }

  SdkCause(this.constraint, this.sdk) : super._();
}

/// The incompatibility represents a package that couldn't be found by its
/// source.
class PackageNotFoundCause extends IncompatibilityCause {
  /// The exception indicating why the package couldn't be found.
  final PackageNotFoundException exception;

  PackageNotFoundCause(this.exception) : super._();

  @override
  String? get hint => exception.hint;
}
