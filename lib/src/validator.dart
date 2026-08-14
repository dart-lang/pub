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
  Uri get serverUrl => context.serverUrl;
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

  /// Run package validation on the [entrypoint] package via `pub_validation`
  /// and print results.
  ///
  /// Installs `pub_validation` using `dart install pub_validation` and executes
  /// the validator CLI.
  static Future<void> runAll(
    Entrypoint entrypoint,
    int packageSize,
    Uri serverUrl,
    List<String> files, {
    required List<String> hints,
    required List<String> warnings,
    required List<String> errors,
  }) async {
    final validationCmd = platform.environment['_PUB_VALIDATION_COMMAND'];
    final validationPath = platform.environment['_PUB_VALIDATION_PATH'];

    StringProcessResult? result;

    if (validationCmd != null) {
      final parts = validationCmd.split(' ');
      result = await runProcess(
        parts.first,
        [
          ...parts.skip(1),
          '-C',
          entrypoint.workPackage.dir,
          '--server-url',
          serverUrl.toString(),
          '--package-size',
          packageSize.toString(),
          '--json',
        ],
      );
    } else if (validationPath != null) {
      result = await runProcess(
        platform.resolvedExecutable,
        [
          'run',
          validationPath,
          '-C',
          entrypoint.workPackage.dir,
          '--server-url',
          serverUrl.toString(),
          '--package-size',
          packageSize.toString(),
          '--json',
        ],
      );
    } else {
      // Install the latest version of pub_validation via `dart install`.
      try {
        final installResult = await runProcess(platform.resolvedExecutable, [
          'install',
          'pub_validation',
        ]);
        if (installResult.exitCode != 0) {
          log.fine('dart install pub_validation: ${installResult.stderr}');
        }
      } catch (e) {
        log.fine('Failed to run dart install pub_validation: $e');
      }

      try {
        result = await runProcess(
          'pub_validation',
          [
            '-C',
            entrypoint.workPackage.dir,
            '--server-url',
            serverUrl.toString(),
            '--package-size',
            packageSize.toString(),
            '--json',
          ],
        );
      } catch (_) {
        // If not on PATH directly, attempt running via `dart run`.
        result = await runProcess(
          platform.resolvedExecutable,
          [
            'run',
            'pub_validation:pub_validation',
            '-C',
            entrypoint.workPackage.dir,
            '--server-url',
            serverUrl.toString(),
            '--package-size',
            packageSize.toString(),
            '--json',
          ],
        );
      }
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
  final Uri serverUrl;
  final List<String> files;

  ValidationContext(
    this.entrypoint,
    this.packageSize,
    this.serverUrl,
    this.files,
  );
}
