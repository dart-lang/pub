// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:pub_semver/pub_semver.dart';

import '../command.dart';
import '../exit_codes.dart' as exit_codes;
import '../io.dart';
import '../log.dart' as log;
import '../package_name.dart';
import '../source/git.dart';
import '../source/hosted.dart';
import '../utils.dart';

/// Handles the `cache repair` pub command.
class CacheRepairCommand extends PubCommand {
  @override
  String get name => 'repair';
  @override
  String get description => 'Reinstall cached packages.';
  @override
  String get docUrl => 'https://dart.dev/tools/pub/cmd/pub-cache';
  @override
  bool get takesArguments => false;

  CacheRepairCommand() {
    argParser.addFlag(
      'all',
      help:
          'Repair all cached packages instead of only packages in the '
          'current pubspec.lock.',
      negatable: false,
    );
  }

  @override
  Future<void> runProtected() async {
    final repairAll = argResults.flag('all');

    // Get the filters for packages to repair (from lockfile if not --all).
    bool Function(String, Version)? hostedPackageFilter;
    bool Function(String, Version)? gitPackageFilter;
    if (!repairAll) {
      if (!entrypoint.canFindWorkspaceRoot) {
        log.message(
          'No pubspec.yaml found. '
          'Run from a Dart project or use --all to repair all cached packages.',
        );
        return;
      }

      if (!fileExists(entrypoint.lockFilePath)) {
        log.message(
          'No pubspec.lock found. '
          'Run "pub get" first or use --all to repair all cached packages.',
        );
        return;
      }

      final lockFile = entrypoint.lockFile;
      final packages = lockFile.packages.values.toList();
      if (packages.isEmpty) {
        log.message('No packages found in pubspec.lock.');
        return;
      }

      (hostedPackageFilter, gitPackageFilter) = _buildPackageFilters(packages);
    }

    // Delete any eventual temp-files left in the cache.
    cache.deleteTempDir();

    // Repair every cached source.
    final repairResults = [
      ...await cache.hosted.repairCachedPackages(
        cache,
        packageFilter: hostedPackageFilter,
      ),
      ...await cache.git.repairCachedPackages(
        cache,
        packageFilter: gitPackageFilter,
      ),
    ];

    final successes = repairResults.where((result) => result.success);
    final failures = repairResults.where((result) => !result.success);

    if (successes.isNotEmpty) {
      final packages = pluralize('package', successes.length);
      log.message(
        'Reinstalled ${log.green(successes.length.toString())} $packages.',
      );
    }

    if (failures.isNotEmpty) {
      final packages = pluralize('package', failures.length);
      final buffer = StringBuffer(
        'Failed to reinstall '
        '${log.red(failures.length.toString())} $packages:\n',
      );

      for (var failure in failures) {
        buffer.write('- ${log.bold(failure.packageName)} ${failure.version}');
        if (failure.source != cache.defaultSource) {
          buffer.write(' from ${failure.source}');
        }
        buffer.writeln();
      }

      log.message(buffer.toString());
    }

    final (repairSuccesses, repairFailures) =
        await globals.repairActivatedPackages();
    if (repairSuccesses.isNotEmpty) {
      final packages = pluralize('package', repairSuccesses.length);
      log.message(
        'Reactivated '
        '${log.green(repairSuccesses.length.toString())} $packages.',
      );
    }

    if (repairFailures.isNotEmpty) {
      final packages = pluralize('package', repairFailures.length);
      log.message(
        'Failed to reactivate '
        '${log.red(repairFailures.length.toString())} $packages:',
      );
      log.message(
        repairFailures.map((name) => '- ${log.bold(name)}').join('\n'),
      );
    }

    if (successes.isEmpty && failures.isEmpty) {
      if (repairAll) {
        log.message('No packages in cache, so nothing to repair.');
      } else {
        log.message('No packages from pubspec.lock found in cache.');
      }
    }

    if (failures.isNotEmpty || repairFailures.isNotEmpty) {
      overrideExitCode(exit_codes.UNAVAILABLE);
    }
  }

  /// Builds source-specific package filters from the lockfile packages.
  ///
  /// Returns a tuple of (hostedFilter, gitFilter).
  /// - Hosted filter: matches by name AND version.
  /// - Git filter: matches by name only (version isn't reliably derivable from
  ///   cache directory names).
  (bool Function(String, Version), bool Function(String, Version))
  _buildPackageFilters(List<PackageId> packages) {
    final hostedPackages =
        packages.where((p) => p.source is HostedSource).toList();
    final gitPackages = packages.where((p) => p.source is GitSource).toList();

    return (
      (name, version) =>
          hostedPackages.any((p) => p.name == name && p.version == version),
      (name, version) => gitPackages.any((p) => p.name == name),
    );
  }
}
