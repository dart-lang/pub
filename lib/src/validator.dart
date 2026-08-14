// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:pub_semver/pub_semver.dart';

import 'entrypoint.dart';
import 'io.dart';
import 'log.dart' as log;
import 'package.dart';
import 'path.dart';
import 'platform_info.dart';
import 'sdk.dart';
import 'system_cache.dart';

/// The base class for validators that check whether a package is fit for
/// uploading.
abstract class Validator {
  /// The accumulated errors for this validator.
  final errors = <String>[];

  /// The accumulated warnings for this validator.
  final warnings = <String>[];

  /// The accumulated hints for this validator.
  final hints = <String>[];

  late ValidationContext context;
  Package get package => context.entrypoint.workPackage;
  SystemCache get cache => context.entrypoint.cache;
  int get packageSize => context.packageSize;
  List<String> get files => context.files;

  /// Validates the entrypoint, adding any errors and warnings to [errors] and
  /// [warnings], respectively.
  Future<void> validate();

  /// Adds an error if the package's SDK constraint doesn't exclude Dart SDK
  /// versions older than [firstSdkVersion].
  @protected
  void validateSdkConstraint(Version firstSdkVersion, String message) {
    if (package.pubspec.dartSdkConstraint.originalConstraint
        .intersect(VersionRange(max: firstSdkVersion))
        .isEmpty) {
      return;
    }

    if (firstSdkVersion.isPreRelease &&
        !_isSamePreRelease(firstSdkVersion, sdk.version)) {
      firstSdkVersion = firstSdkVersion.nextPatch;
    }

    final allowedSdks = VersionRange(
      min: firstSdkVersion,
      includeMin: true,
      max:
          firstSdkVersion.isPreRelease
              ? firstSdkVersion.nextPatch
              : firstSdkVersion.nextBreaking,
    );

    var newSdkConstraint = package.pubspec.dartSdkConstraint.originalConstraint
        .intersect(allowedSdks);
    if (newSdkConstraint.isEmpty) newSdkConstraint = allowedSdks;

    errors.add(
      '$message\n'
      'Make sure your SDK constraint excludes old versions:\n'
      '\n'
      'environment:\n'
      '  sdk: "${newSdkConstraint.asCompatibleWithIfPossible()}"',
    );
  }

  bool _isSamePreRelease(Version version1, Version version2) =>
      version1.isPreRelease &&
      version2.isPreRelease &&
      version1.patch == version2.patch &&
      version1.minor == version2.minor &&
      version1.major == version2.major;

  /// The default package descriptor used for package validation.
  static const defaultValidationPackage = 'pub_validation@^0.1.0';

  /// The default trusted repository URL for installing validation tools.
  static const defaultValidationHostedUrl = 'https://pub.dev';

  /// Run package validation on the [entrypoint] package via `pub_validation`
  /// and print results.
  ///
  /// Installs `pub_validation` using `dart install` and executes the
  /// validator CLI.
  static Future<void> runAll(
    Entrypoint entrypoint,
    int packageSize,
    List<String> files, {
    required List<String> hints,
    required List<String> warnings,
    required List<String> errors,
    String? validationPackage,
    Uri? validationHostedUrl,
  }) async {
    final pkgDescriptor = validationPackage ?? defaultValidationPackage;
    final pkgName = pkgDescriptor.split('@').first;
    final hostedUrl =
        (validationHostedUrl ?? Uri.parse(defaultValidationHostedUrl))
            .toString();

    // Install the validation package via `dart install`.
    try {
      final installResult = await runProcess(platform.resolvedExecutable, [
        'install',
        pkgDescriptor,
        '--hosted-url',
        hostedUrl,
      ]);
      if (installResult.exitCode != 0) {
        log.fine('dart install $pkgDescriptor: ${installResult.stderr}');
      }
    } catch (e) {
      log.fine('Failed to run dart install $pkgDescriptor: $e');
    }

    StringProcessResult result;
    try {
      result = await runProcess(pkgName, [
        '-C',
        entrypoint.workPackage.dir,
        '--package-size',
        packageSize.toString(),
        '--json',
      ]);
    } catch (_) {
      // If not on PATH directly, attempt running via `dart run`.
      result = await runProcess(platform.resolvedExecutable, [
        'run',
        '$pkgName:$pkgName',
        '-C',
        entrypoint.workPackage.dir,
        '--package-size',
        packageSize.toString(),
        '--json',
      ]);
    }

    try {
      final stdout = result.stdout;
      final jsonStart = stdout.indexOf('{');
      if (jsonStart != -1) {
        final jsonStr = stdout.substring(jsonStart);
        final decoded = json.decode(jsonStr) as Map<String, dynamic>;
        if (decoded['errors'] is List) {
          errors.addAll((decoded['errors'] as List).cast<String>());
        }
        if (decoded['warnings'] is List) {
          warnings.addAll((decoded['warnings'] as List).cast<String>());
        }
        if (decoded['hints'] is List) {
          hints.addAll((decoded['hints'] as List).cast<String>());
        }
      } else if (result.exitCode != 0) {
        errors.add(stdout.isNotEmpty ? stdout : result.stderr);
      }
    } catch (e) {
      log.fine('Failed to parse pub_validation output: $e');
    }

    String presentDiagnostics(List<String> diagnostics) => diagnostics
        .map((diagnostic) => "* ${diagnostic.split('\n').join('\n  ')}\n")
        .join('\n');
    final sections = <String>[];

    for (final (kind, diagnostics) in [
      ('error', errors),
      ('potential issue', warnings),
      ('hint', hints),
    ]) {
      if (diagnostics.isNotEmpty) {
        final s = diagnostics.length > 1 ? 's' : '';
        final count = diagnostics.length > 1 ? '${diagnostics.length} ' : '';
        sections.add(
          'Package validation found the following $count$kind$s:\n'
          '${presentDiagnostics(diagnostics)}',
        );
      }
    }
    if (sections.isNotEmpty) {
      log.message(sections.join('\n'));
    }
  }

  /// Returns the [files] that are [path] or inside [path] (relative to the
  /// package entrypoint).
  List<String> filesBeneath(String path, {required bool recursive}) {
    final base = p.canonicalize(p.join(package.dir, path));
    return files
        .where(
          recursive
              ? (file) =>
                  p.isWithin(base, p.canonicalize(file)) ||
                  p.canonicalize(file) == base
              : (file) => p.canonicalize(p.dirname(file)) == base,
        )
        .toList();
  }
}

class ValidationContext {
  final Entrypoint entrypoint;
  final int packageSize;
  final List<String> files;

  ValidationContext(this.entrypoint, this.packageSize, this.files);
}
