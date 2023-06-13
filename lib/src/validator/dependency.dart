// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:pub_semver/pub_semver.dart';

import '../exceptions.dart';
import '../log.dart' as log;
import '../package_name.dart';
import '../sdk.dart';
import '../source/hosted.dart';
import '../source/path.dart';
import '../source/sdk.dart';
import '../validator.dart';

/// A validator that validates a package's dependencies.
class DependencyValidator extends Validator {
  @override
  Future validate() async {
    /// Whether any dependency has a caret constraint.
    var hasCaretDep = false;

    /// Emit an error for dependencies from unknown SDKs or without appropriate
    /// constraints on the Dart SDK.
    void warnAboutSdkSource(PackageRange dep) {
      var identifier = (dep.description as SdkDescription).sdk;
      var sdk = sdks[identifier];
      if (sdk == null) {
        errors.add('Unknown SDK "$identifier" for dependency "${dep.name}".');
        return;
      }
    }

    /// Warn that dependencies should use the hosted source.
    Future warnAboutSource(PackageRange dep) async {
      List<Version> versions;
      try {
        var ids = await entrypoint.cache
            .getVersions(entrypoint.cache.hosted.refFor(dep.name));
        versions = ids.map((id) => id.version).toList();
      } on ApplicationException catch (_) {
        versions = [];
      }

      String constraint;
      if (versions.isNotEmpty) {
        constraint = '^${Version.primary(versions)}';
      } else {
        constraint = dep.constraint.toString();
        if (!dep.constraint.isAny && dep.constraint is! Version) {
          constraint = '"$constraint"';
        }
      }

      // Path sources are errors. Other sources are just warnings.
      var messages = dep.source is PathSource ? errors : warnings;

      messages.add('Don\'t depend on "${dep.name}" from the ${dep.source} '
          'source. Use the hosted source instead. For example:\n'
          '\n'
          'dependencies:\n'
          '  ${dep.name}: $constraint\n'
          '\n'
          'Using the hosted source ensures that everyone can download your '
          'package\'s dependencies along with your package.');
    }

    /// Warn about improper dependencies on Flutter.
    void warnAboutFlutterSdk(PackageRange dep) {
      if (dep.source is SdkSource) {
        warnAboutSdkSource(dep);
        return;
      }

      errors.add('Don\'t depend on "${dep.name}" from the ${dep.source} '
          'source. Use the SDK source instead. For example:\n'
          '\n'
          'dependencies:\n'
          '  ${dep.name}:\n'
          '    sdk: ${dep.constraint}\n'
          '\n'
          'The Flutter SDK is downloaded and managed outside of pub.');
    }

    /// Warn that dependencies should have version constraints.
    void warnAboutNoConstraint(PackageRange dep) {
      var message = 'Your dependency on "${dep.name}" should have a version '
          'constraint.';
      var locked = entrypoint.lockFile.packages[dep.name];
      if (locked != null) {
        message = '$message For example:\n'
            '\n'
            'dependencies:\n'
            '  ${dep.name}: ^${locked.version}\n';
      }
      warnings.add('$message\n'
          'Without a constraint, you\'re promising to support ${log.bold("all")} '
          'future versions of "${dep.name}".');
    }

    /// Warn that dependencies should allow more than a single version.
    void warnAboutSingleVersionConstraint(PackageRange dep) {
      warnings.add(
          'Your dependency on "${dep.name}" should allow more than one version. '
          'For example:\n'
          '\n'
          'dependencies:\n'
          '  ${dep.name}: ^${dep.constraint}\n'
          '\n'
          'Constraints that are too tight will make it difficult for people to '
          'use your package\n'
          'along with other packages that also depend on "${dep.name}".');
    }

    /// Warn that dependencies should have lower bounds on their constraints.
    void warnAboutNoConstraintLowerBound(PackageRange dep) {
      var message =
          'Your dependency on "${dep.name}" should have a lower bound.';
      var locked = entrypoint.lockFile.packages[dep.name];
      if (locked != null) {
        String constraint;
        if (locked.version == (dep.constraint as VersionRange).max) {
          constraint = '^${locked.version}';
        } else {
          constraint = '">=${locked.version} ${dep.constraint}"';
        }

        message = '$message For example:\n'
            '\n'
            'dependencies:\n'
            '  ${dep.name}: $constraint\n';
      }
      warnings.add('$message\n'
          'Without a constraint, you\'re promising to support ${log.bold("all")} '
          'previous versions of "${dep.name}".');
    }

    /// Warn that dependencies should have upper bounds on their constraints.
    void warnAboutNoConstraintUpperBound(PackageRange dep) {
      String constraint;
      if ((dep.constraint as VersionRange).includeMin) {
        constraint = '^${(dep.constraint as VersionRange).min}';
      } else {
        constraint = '"${dep.constraint} '
            '<${(dep.constraint as VersionRange).min!.nextBreaking}"';
      }
      // TODO: Handle the case where `dep.constraint.min` is null.

      warnings.add(
          'Your dependency on "${dep.name}" should have an upper bound. For '
          'example:\n'
          '\n'
          'dependencies:\n'
          '  ${dep.name}: $constraint\n'
          '\n'
          'Without an upper bound, you\'re promising to support '
          '${log.bold("all")} future versions of ${dep.name}.');
    }

    void warnAboutPrerelease(String dependencyName, VersionRange constraint) {
      final packageVersion = entrypoint.root.version;
      if (constraint.min != null &&
          constraint.min!.isPreRelease &&
          !packageVersion.isPreRelease) {
        warnings.add('Packages dependent on a pre-release of another package '
            'should themselves be published as a pre-release version. '
            'If this package needs $dependencyName version ${constraint.min}, '
            'consider publishing the package as a pre-release instead.\n'
            'See https://dart.dev/tools/pub/publishing#publishing-prereleases '
            'For more information on pre-releases.');
      }
    }

    /// Validates all dependencies in [dependencies].
    Future validateDependencies(Iterable<PackageRange> dependencies) async {
      for (var dependency in dependencies) {
        var constraint = dependency.constraint;
        if (dependency.name == 'flutter') {
          warnAboutFlutterSdk(dependency);
        } else if (dependency.source is SdkSource) {
          warnAboutSdkSource(dependency);
        } else if (dependency.source is! HostedSource) {
          await warnAboutSource(dependency);
        } else {
          if (constraint.isAny) {
            warnAboutNoConstraint(dependency);
          } else if (constraint is VersionRange) {
            if (constraint is Version) {
              warnAboutSingleVersionConstraint(dependency);
            } else {
              warnAboutPrerelease(dependency.name, constraint);
              if (constraint.min == null) {
                warnAboutNoConstraintLowerBound(dependency);
              } else if (constraint.max == null) {
                warnAboutNoConstraintUpperBound(dependency);
              }
            }
            hasCaretDep = hasCaretDep || constraint.toString().startsWith('^');
          }
        }
      }
    }

    await validateDependencies(entrypoint.root.pubspec.dependencies.values);
  }
}
