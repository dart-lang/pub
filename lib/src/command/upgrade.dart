// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:yaml_edit/yaml_edit.dart';

import '../command.dart';
import '../entrypoint.dart';
import '../io.dart';
import '../log.dart' as log;
import '../package.dart';
import '../package_name.dart';
import '../pubspec_utils.dart';
import '../solver.dart';
import '../source/hosted.dart';

/// Handles the `upgrade` pub command.
class UpgradeCommand extends PubCommand {
  @override
  String get name => 'upgrade';
  @override
  String get description =>
      "Upgrade the current package's dependencies to latest versions.";
  @override
  String get invocation => 'pub upgrade [dependencies...]';
  @override
  String get docUrl => 'https://dart.dev/tools/pub/cmd/pub-upgrade';

  @override
  bool get isOffline => argResults['offline'];

  /// Avoid showing spinning progress messages when not in a terminal.
  bool get _shouldShowSpinner => stdout.hasTerminal;

  UpgradeCommand() {
    argParser.addFlag('offline',
        help: 'Use cached packages instead of accessing the network.');

    argParser.addFlag('dry-run',
        abbr: 'n',
        negatable: false,
        help: "Report what dependencies would change but don't change any.");

    argParser.addFlag('precompile',
        help: 'Precompile executables in immediate dependencies.');

    argParser.addFlag('packages-dir', hide: true);

    argParser.addFlag('breaking',
        help: 'Upgrades packages to their latest resolvable version, '
            'and updates pubspec.yaml.',
        negatable: false);
  }

  @override
  Future run() async {
    if (argResults.wasParsed('packages-dir')) {
      log.warning(log.yellow(
          'The --packages-dir flag is no longer used and does nothing.'));
    }

    if (argResults['breaking']) {
      final upgradeOnly = argResults.rest;
      final rootPubspec = entrypoint.root.pubspec;
      final allDependencies = [
        ...rootPubspec.dependencies.values,
        ...rootPubspec.devDependencies.values
      ];

      final resolvablePubspec =
          removeVersionUpperBounds(rootPubspec, upgradeOnly: upgradeOnly);

      /// Solve [resolvablePubspec] and consolidate the resolved versions of the
      /// packages into a map for quick searching.
      final resolvablePackages = <String, PackageId>{};
      await log.spinner('Resolving', () async {
        final solveResult = await tryResolveVersions(
          SolveType.UPGRADE,
          cache,
          Package.inMemory(resolvablePubspec),
        );

        final resolvedPackages = solveResult?.packages ?? [];

        for (final resolvedPackage in resolvedPackages) {
          resolvablePackages[resolvedPackage.name] = resolvedPackage;
        }
      }, condition: _shouldShowSpinner);

      /// Consolidate the changes that will be made to `pubspec.yaml`.
      final dependencyChanges = <PackageRange, PackageId>{};

      for (final package in allDependencies) {
        final resolvedPackage = resolvablePackages[package.name];

        /// If packages were specified on the command line, [dependencyChanges]
        /// will only contain the changes made to those packages since we do
        /// not modify the package constraints of other packages, so there is
        /// never a case where
        /// `!package.constraint.allows(resolvedPackage.version)` evaluates to
        /// true.
        if (resolvedPackage != null &&
            !package.constraint.allows(resolvedPackage.version) &&
            package.source is HostedSource) {
          dependencyChanges[package] = resolvedPackage;
        }
      }

      if (!argResults['dry-run']) {
        await _updatePubspec(dependencyChanges);
      }

      _outputBreakingChangeSummary(dependencyChanges);
    }

    await Entrypoint.current(cache).acquireDependencies(SolveType.UPGRADE,
        useLatest: argResults.rest,
        dryRun: argResults['dry-run'],
        precompile: argResults['precompile']);

    if (isOffline) {
      log.warning('Warning: Upgrading when offline may not update you to the '
          'latest versions of your dependencies.');
    }
  }

  /// Writes the differences between [resolvedPackages] and the current
  /// dependencies to the pubspec file.
  Future<void> _updatePubspec(
      Map<PackageRange, PackageId> dependencyChanges) async {
    ArgumentError.checkNotNull(dependencyChanges, 'dependencyChanges');

    if (dependencyChanges.isEmpty) return;

    final yamlEditor = YamlEditor(readTextFile(entrypoint.pubspecPath));
    final initialDependencies = entrypoint.root.pubspec.dependencies.keys;
    final initialDevDependencies = entrypoint.root.pubspec.devDependencies.keys;

    for (final finalPackage in dependencyChanges.values) {
      if (initialDependencies.contains(finalPackage.name)) {
        yamlEditor.update(
            ['dependencies', finalPackage.name], '^${finalPackage.version}');
      } else if (initialDevDependencies.contains(finalPackage.name)) {
        yamlEditor.update(['dev_dependencies', finalPackage.name],
            '^${finalPackage.version}');
      }
    }

    /// Windows line endings are already handled by [yamlEditor]
    writeTextFile(entrypoint.pubspecPath, yamlEditor.toString());
  }
}

/// Outputs a summary of breaking changes that will be made.
void _outputBreakingChangeSummary(
    Map<PackageRange, PackageId> dependencyChanges) {
  ArgumentError.checkNotNull(dependencyChanges, 'dependencyChanges');

  if (dependencyChanges.isEmpty) {
    log.message('No breaking changes detected!');
  } else {
    final s = dependencyChanges.length == 1 ? '' : 's';

    log.message(
        'Detected ${dependencyChanges.length} potential breaking change$s:');

    for (final change in dependencyChanges.entries) {
      final initialPackage = change.key;
      final finalPackage = change.value;

      log.message('${initialPackage.name}: ${initialPackage.constraint} -> '
          '^${finalPackage.version}');
    }
  }
}
