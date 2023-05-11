// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub_semver/pub_semver.dart';

import '../exceptions.dart';
import '../language_version.dart';
import '../package_name.dart';
import '../sdk.dart';
import '../source/sdk.dart';
import 'incompatibility.dart';

/// The reason an [Incompatibility]'s terms are incompatible.
sealed class IncompatibilityCause {
  IncompatibilityCause();

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

/// The incompatibility represents the requirement that the root package
/// exists.
class RootIncompatibilityCause extends IncompatibilityCause {}

/// The incompatibility represents a package's dependency.
class DependencyIncompatibilityCause extends IncompatibilityCause {
  final PackageRange depender;
  final PackageRange target;
  DependencyIncompatibilityCause(this.depender, this.target);

  @override
  String? get notice {
    final dependerDescription = depender.description;
    if (dependerDescription is SdkDescription) {
      final targetConstraint = target.constraint;
      if (targetConstraint is Version) {
        return '''
Note: ${target.name} is pinned to version $targetConstraint by ${depender.name} from the ${dependerDescription.sdk} SDK.
See https://dart.dev/go/version-pinning for details.
''';
      }
    }
    return null;
  }
}

/// The incompatibility indicates that the package has no versions that match
/// the given constraint.
class NoVersionsIncompatibilityCause extends IncompatibilityCause {}

/// The incompatibility indicates that the package has an unknown source.
class UnknownSourceIncompatibilityCause extends IncompatibilityCause {}

/// The incompatibility was derived from two existing incompatibilities during
/// conflict resolution.
class ConflictCause extends IncompatibilityCause {
  /// The incompatibility that was originally found to be in conflict, from
  /// which the target incompatibility was derived.
  final Incompatibility conflict;

  /// The incompatibility that caused the most recent satisfier for [conflict],
  /// from which the target incompatibility was derived.
  final Incompatibility other;

  ConflictCause(this.conflict, this.other);
}

/// The incompatibility represents a package's SDK constraint being
/// incompatible with the current SDK.
class SdkIncompatibilityCause extends IncompatibilityCause {
  /// The union of all the incompatible versions' constraints on the SDK.
  // TODO(zarah): Investigate if this can be non-nullable
  final VersionConstraint? constraint;

  /// The SDK with which the package was incompatible.
  final Sdk sdk;

  bool get noNullSafetyCause =>
      sdk.isDartSdk &&
      !LanguageVersion.fromSdkConstraint(constraint).supportsNullSafety &&
      sdk.version! >= Version(3, 0, 0).firstPreRelease;

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
    if (noNullSafetyCause) {
      return 'The lower bound of "sdk: \'$constraint\'" must be 2.12.0'
          ' or higher to enable null safety.'
          '\nFor details, see https://dart.dev/null-safety';
    }
    // If the SDK is available, then installing it won't help
    if (sdk.isAvailable) {
      return null;
    }
    // Return an install message for the SDK, if there is an install message.
    return sdk.installMessage;
  }

  SdkIncompatibilityCause(this.constraint, this.sdk);
}

/// The incompatibility represents a package that couldn't be found by its
/// source.
class PackageNotFoundIncompatibilityCause extends IncompatibilityCause {
  /// The exception indicating why the package couldn't be found.
  final PackageNotFoundException exception;

  PackageNotFoundIncompatibilityCause(this.exception);

  @override
  String? get hint => exception.hint;
}
