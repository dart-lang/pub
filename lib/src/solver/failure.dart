// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:pub_semver/pub_semver.dart';
import 'package:stack_trace/stack_trace.dart';

import '../exceptions.dart';
import '../log.dart' as log;
import '../package_name.dart';
import 'dependency.dart';

/// Base class for all failures that can occur while trying to resolve versions.
abstract class SolveFailure implements ApplicationException {
  /// The name of the package whose version could not be solved.
  ///
  /// Will be `null` if the failure is not specific to one package.
  final String package;

  /// The known dependencies on [package] at the time of the failure.
  ///
  /// Will be an empty collection if the failure is not specific to one package.
  final Iterable<Dependency> dependencies;

  String get message => toString();

  /// A message describing the specific kind of solve failure.
  String get _message {
    throw new UnimplementedError("Must override _message or toString().");
  }

  SolveFailure(this.package, Iterable<Dependency> dependencies)
      : dependencies = dependencies != null ? dependencies : <Dependency>[];

  String toString() {
    if (dependencies.isEmpty) return _message;

    var buffer = new StringBuffer();
    buffer.write("$_message:");

    var sorted = dependencies.toList();
    sorted.sort((a, b) => a.depender.name.compareTo(b.depender.name));

    for (var dep in sorted) {
      buffer.writeln();
      buffer.write("- ${log.bold(dep.depender.name)}");
      if (!dep.depender.isMagic && !dep.depender.isRoot) {
        buffer.write(" ${dep.depender.version}");
      }
      buffer.write(" ${_describeDependency(dep.dep)}");
    }

    return buffer.toString();
  }

  /// Describes a dependency's reference in the output message.
  ///
  /// Override this to highlight which aspect of [dep] led to the failure.
  String _describeDependency(PackageRange dep) {
    var description = "depends on version ${dep.constraint}";
    if (dep.features.isNotEmpty) description += " ${dep.featureDescription}";
    return description;
  }
}

/// Exception thrown when the current SDK's version does not match a package's
/// constraint on it.
class BadSdkVersionException extends SolveFailure {
  final String _message;

  BadSdkVersionException(String package, String message)
      : _message = message,
        super(package, null);
}

/// Exception thrown when the [VersionConstraint] used to match a package is
/// valid (i.e. non-empty), but there are no available versions of the package
/// that fit that constraint.
class NoVersionException extends SolveFailure {
  final VersionConstraint constraint;

  /// The last selected version of the package that failed to meet the new
  /// constraint.
  ///
  /// This will be `null` when the failure occurred because there are no
  /// versions of the package *at all* that match the constraint. It will be
  /// non-`null` when a version was selected, but then the solver tightened a
  /// constraint such that that version was no longer allowed.
  final Version version;

  NoVersionException(String package, this.version, this.constraint,
      Iterable<Dependency> dependencies)
      : super(package, dependencies);

  String get _message {
    if (version == null) {
      return "Package $package has no versions that match $constraint derived "
          "from";
    }

    return "Package $package $version does not match $constraint derived from";
  }
}

// TODO(rnystrom): Report the list of depending packages and their constraints.
/// Exception thrown when the most recent version of [package] must be selected,
/// but doesn't match the [VersionConstraint] imposed on the package.
class CouldNotUpgradeException extends SolveFailure {
  final VersionConstraint constraint;
  final Version best;

  CouldNotUpgradeException(String package, this.constraint, this.best)
      : super(package, null);

  String get _message =>
      "The latest version of $package, $best, does not match $constraint.";
}

/// Exception thrown when the [VersionConstraint] used to match a package is
/// the empty set: in other words, multiple packages depend on it and have
/// conflicting constraints that have no overlap.
class DisjointConstraintException extends SolveFailure {
  DisjointConstraintException(String package, Iterable<Dependency> dependencies)
      : super(package, dependencies);

  String get _message => "Incompatible version constraints on $package";
}

/// Exception thrown when two packages with the same name but different sources
/// are depended upon.
class SourceMismatchException extends SolveFailure {
  String get _message => "Incompatible dependencies on $package";

  SourceMismatchException(String package, Iterable<Dependency> dependencies)
      : super(package, dependencies);

  String _describeDependency(PackageRange dep) =>
      "depends on it from source ${dep.source}";
}

/// Exception thrown when a dependency on an unknown source name is found.
class UnknownSourceException extends SolveFailure {
  UnknownSourceException(String package, Iterable<Dependency> dependencies)
      : super(package, dependencies);

  String toString() {
    var dep = dependencies.single;
    return 'Package ${dep.depender.name} depends on ${dep.dep.name} from '
        'unknown source "${dep.dep.source}".';
  }
}

/// Exception thrown when two packages with the same name and source but
/// different descriptions are depended upon.
class DescriptionMismatchException extends SolveFailure {
  String get _message => "Incompatible dependencies on $package";

  DescriptionMismatchException(
      String package, Iterable<Dependency> dependencies)
      : super(package, dependencies);

  String _describeDependency(PackageRange dep) {
    // TODO(nweiz): Dump descriptions to YAML when that's supported.
    return "depends on it with description ${JSON.encode(dep.description)}";
  }
}

/// Exception thrown when a dependency could not be found in its source.
///
/// Unlike [PackageNotFoundException], this includes information about the
/// dependent packages requesting the missing one.
class DependencyNotFoundException extends SolveFailure
    implements WrappedException {
  final PackageNotFoundException innerError;
  Chain get innerChain => innerError.innerChain;

  String get _message => "${innerError.message}\nDepended on by";

  DependencyNotFoundException(
      String package, this.innerError, Iterable<Dependency> dependencies)
      : super(package, dependencies);

  /// The failure isn't because of the version of description of the package,
  /// it's the package itself that can't be found, so just show the name and no
  /// descriptive details.
  String _describeDependency(PackageRange dep) => "";
}

/// An exception thrown when a dependency requires a feature that doesn't exist.
class MissingFeatureException extends SolveFailure {
  final Version version;
  final String feature;

  String get _message =>
      "$package $version doesn't have a feature named $feature";

  MissingFeatureException(String package, this.version, this.feature,
      Iterable<Dependency> dependencies)
      : super(package, dependencies);
}
