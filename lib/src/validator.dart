// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:pub_semver/pub_semver.dart';

import 'entrypoint.dart';
import 'log.dart' as log;
import 'utils.dart';
import 'validator/compiled_dartdoc.dart';
import 'validator/dependency.dart';
import 'validator/dependency_override.dart';
import 'validator/directory.dart';
import 'validator/executable.dart';
import 'validator/license.dart';
import 'validator/name.dart';
import 'validator/pubspec.dart';
import 'validator/pubspec_field.dart';
import 'validator/readme.dart';
import 'validator/sdk_constraint.dart';
import 'validator/size.dart';
import 'validator/strict_dependencies.dart';

/// The base class for validators that check whether a package is fit for
/// uploading.
///
/// Each validator should override [errors], [warnings], or both to return
/// lists of errors or warnings to display to the user. Errors will cause the
/// package not to be uploaded; warnings will require the user to confirm the
/// upload.
abstract class Validator {
  /// The entrypoint that's being validated.
  final Entrypoint entrypoint;

  /// The accumulated errors for this validator.
  ///
  /// Filled by calling [validate].
  final errors = <String>[];

  /// The accumulated warnings for this validator.
  ///
  /// Filled by calling [validate].
  final warnings = <String>[];

  Validator(this.entrypoint);

  /// Validates the entrypoint, adding any errors and warnings to [errors] and
  /// [warnings], respectively.
  Future validate();

  /// Adds an error if the package's SDK constraint doesn't exclude Dart SDK
  /// versions older than [firstSdkVersion].
  @protected
  void validateSdkConstraint(Version firstSdkVersion, String message) {
    // If the SDK constraint disallowed all versions before [firstSdkVersion],
    // no error is necessary.
    if (entrypoint.root.pubspec.originalDartSdkConstraint
        .intersect(new VersionRange(max: firstSdkVersion))
        .isEmpty) {
      return;
    }

    // Suggest that users use a non-dev SDK constraint, even if there were some
    // dev versions that are allowed.
    var nextNonDevVersion = firstSdkVersion.isPreRelease
        ? firstSdkVersion.nextMinor
        : firstSdkVersion;
    var allowedSdks =
        new VersionConstraint.compatibleWith(nextNonDevVersion) as VersionRange;

    // Avoid ^ constraints, since they aren't supported in SDK constraints.
    allowedSdks = new VersionRange(
        min: allowedSdks.min,
        max: allowedSdks.max,
        includeMin: allowedSdks.includeMin,
        includeMax: allowedSdks.includeMax);

    var newSdkConstraint = entrypoint.root.pubspec.originalDartSdkConstraint
        .intersect(allowedSdks);
    if (newSdkConstraint.isEmpty) newSdkConstraint = allowedSdks;

    errors.add("$message\n"
        "Make sure your SDK constraint excludes old versions:\n"
        "\n"
        "environment:\n"
        "  sdk: \"$newSdkConstraint\"");
  }

  /// Run all validators on the [entrypoint] package and print their results.
  ///
  /// The future completes with the error and warning messages, respectively.
  ///
  /// [packageSize], if passed, should complete to the size of the tarred
  /// package, in bytes. This is used to validate that it's not too big to
  /// upload to the server.
  static Future<Pair<List<String>, List<String>>> runAll(Entrypoint entrypoint,
      [Future<int> packageSize]) {
    var validators = [
      new PubspecValidator(entrypoint),
      new LicenseValidator(entrypoint),
      new NameValidator(entrypoint),
      new PubspecFieldValidator(entrypoint),
      new DependencyValidator(entrypoint),
      new DependencyOverrideValidator(entrypoint),
      new DirectoryValidator(entrypoint),
      new ExecutableValidator(entrypoint),
      new CompiledDartdocValidator(entrypoint),
      new ReadmeValidator(entrypoint),
      new SdkConstraintValidator(entrypoint),
      new StrictDependenciesValidator(entrypoint),
    ];
    if (packageSize != null) {
      validators.add(new SizeValidator(entrypoint, packageSize));
    }

    return Future
        .wait(validators.map((validator) => validator.validate()))
        .then((_) {
      var errors = validators.expand((validator) => validator.errors).toList();
      var warnings =
          validators.expand((validator) => validator.warnings).toList();

      if (errors.isNotEmpty) {
        log.error("Missing requirements:");
        for (var error in errors) {
          log.error("* ${error.split('\n').join('\n  ')}");
        }
        log.error("");
      }

      if (warnings.isNotEmpty) {
        log.warning("Suggestions:");
        for (var warning in warnings) {
          log.warning("* ${warning.split('\n').join('\n  ')}");
        }
        log.warning("");
      }

      return new Pair<List<String>, List<String>>(errors, warnings);
    });
  }
}
