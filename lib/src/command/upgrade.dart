// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:pub_semver/pub_semver.dart';

import '../command.dart';
import '../command_runner.dart';
import '../entrypoint.dart';
import '../io.dart';
import '../log.dart' as log;
import '../package.dart';
import '../package_name.dart';
import '../pubspec.dart';
import '../pubspec_utils.dart';
import '../solver.dart';
import '../source/hosted.dart';
import '../utils.dart';

/// Handles the `upgrade` pub command.
class UpgradeCommand extends PubCommand {
  @override
  String get name => 'upgrade';
  @override
  String get description =>
      "Upgrade the current package's dependencies to latest versions.";
  @override
  String get argumentsDescription => '[dependencies...]';
  @override
  String get docUrl => 'https://dart.dev/tools/pub/cmd/pub-upgrade';

  @override
  bool get isOffline => argResults.flag('offline');

  UpgradeCommand() {
    argParser.addFlag(
      'offline',
      help: 'Use cached packages instead of accessing the network.',
    );

    argParser.addFlag(
      'dry-run',
      abbr: 'n',
      negatable: false,
      help: "Report what dependencies would change but don't change any.",
    );

    argParser.addFlag(
      'precompile',
      help: 'Precompile executables in immediate dependencies.',
    );

    argParser.addFlag(
      'null-safety',
      hide: true,
      negatable: false,
      help: 'Upgrade constraints in pubspec.yaml to null-safety versions',
    );
    argParser.addFlag('nullsafety', negatable: false, hide: true);

    argParser.addFlag('packages-dir', hide: true);

    argParser.addFlag(
      'tighten',
      help:
          'Updates lower bounds in pubspec.yaml to match the resolved version.',
      negatable: false,
    );

    argParser.addFlag(
      'major-versions',
      help: 'Upgrades packages to their latest resolvable versions, '
          'and updates pubspec.yaml.',
      negatable: false,
    );

    argParser.addFlag(
      'example',
      defaultsTo: true,
      help: 'Also run in `example/` (if it exists).',
      hide: true,
    );

    argParser.addOption(
      'directory',
      abbr: 'C',
      help: 'Run this in the directory <dir>.',
      valueHelp: 'dir',
    );
  }

  /// Avoid showing spinning progress messages when not in a terminal.
  bool get _shouldShowSpinner => terminalOutputForStdout;

  bool get _dryRun => argResults.flag('dry-run');

  bool get _tighten => argResults.flag('tighten');

  bool get _precompile => argResults.flag('precompile');

  /// List of package names to upgrade, if empty then upgrade all packages.
  ///
  /// This allows the user to specify list of names that they want the
  /// upgrade command to affect.
  List<String> get _packagesToUpgrade => argResults.rest;

  bool get _upgradeNullSafety =>
      argResults.flag('nullsafety') || argResults.flag('null-safety');

  bool get _upgradeMajorVersions => argResults.flag('major-versions');

  @override
  Future<void> runProtected() async {
    if (_upgradeNullSafety) {
      dataError('''The `--null-safety` flag is no longer supported.
Consider using the Dart 2.19 sdk to migrate to null safety.''');
    }
    if (argResults.wasParsed('packages-dir')) {
      log.warning(
        log.yellow(
          'The --packages-dir flag is no longer used and does nothing.',
        ),
      );
    }

    if (_upgradeMajorVersions) {
      if (argResults.flag('example') && entrypoint.example != null) {
        log.warning(
          'Running `upgrade --major-versions` only in `${entrypoint.workspaceRoot.dir}`. Run `$topLevelProgram pub upgrade --major-versions --directory example/` separately.',
        );
      }
      await _runUpgradeMajorVersions();
    } else {
      await _runUpgrade(entrypoint);
      if (_tighten) {
        if (argResults.flag('example') && entrypoint.example != null) {
          log.warning(
            'Running `upgrade --tighten` only in `${entrypoint.workspaceRoot.dir}`. Run `$topLevelProgram pub upgrade --tighten --directory example/` separately.',
          );
        }
        final changes =
            entrypoint.tighten(packagesToUpgrade: _packagesToUpgrade);
        entrypoint.applyChanges(changes, _dryRun);
      }
    }
    if (argResults.flag('example') && entrypoint.example != null) {
      // Reload the entrypoint to ensure we pick up potential changes that has
      // been made.
      final exampleEntrypoint = Entrypoint(directory, cache).example!;
      await _runUpgrade(exampleEntrypoint, onlySummary: true);
    }
  }

  Future<void> _runUpgrade(Entrypoint e, {bool onlySummary = false}) async {
    await e.acquireDependencies(
      SolveType.upgrade,
      unlock: _packagesToUpgrade,
      dryRun: _dryRun,
      precompile: _precompile,
      summaryOnly: onlySummary,
    );

    _showOfflineWarning();
  }

  /// Return names of packages to be upgraded, and throws [UsageException] if
  /// any package names not in the direct dependencies or dev_dependencies are given.
  ///
  /// This assumes that `--major-versions` was passed.
  List<String> _directDependenciesToUpgrade() {
    assert(_upgradeMajorVersions);

    final directDeps = {
      for (final package in entrypoint.workspaceRoot.transitiveWorkspace) ...[
        ...package.dependencies.keys,
        ...package.devDependencies.keys,
      ],
    }.toList();
    final toUpgrade =
        _packagesToUpgrade.isEmpty ? directDeps : _packagesToUpgrade;

    // Check that all package names in upgradeOnly are direct-dependencies
    final notInDeps = toUpgrade.where((n) => !directDeps.contains(n));
    if (toUpgrade.any(notInDeps.contains)) {
      usageException('''
Dependencies specified in `$topLevelProgram pub upgrade --major-versions <dependencies>` must
be direct 'dependencies' or 'dev_dependencies', following packages are not:
 - ${notInDeps.join('\n - ')}

''');
    }

    return toUpgrade;
  }

  Future<void> _runUpgradeMajorVersions() async {
    final toUpgrade = _directDependenciesToUpgrade();
    // Solve [resolvablePubspec] in-memory and consolidate the resolved
    // versions of the packages into a map for quick searching.
    final resolvedPackages = <String, PackageId>{};
    final solveResult = await log.spinner(
      'Resolving dependencies',
      () async {
        return await resolveVersions(
          SolveType.upgrade,
          cache,
          entrypoint.workspaceRoot.transformWorkspace(
            (package) => stripVersionBounds(package.pubspec),
          ),
        );
      },
      condition: _shouldShowSpinner,
    );
    for (final resolvedPackage in solveResult.packages) {
      resolvedPackages[resolvedPackage.name] = resolvedPackage;
    }
    final dependencyOverriddenDeps = <String>[];
    // Changes to be made to `pubspec.yaml` of each package.
    // Mapping from original to changed value.
    var changes = <Package, Map<PackageRange, PackageRange>>{};
    for (final package in entrypoint.workspaceRoot.transitiveWorkspace) {
      final declaredHostedDependencies = [
        ...package.dependencies.values,
        ...package.devDependencies.values,
      ].where((dep) => dep.source is HostedSource);
      for (final dep in declaredHostedDependencies) {
        final resolvedPackage = resolvedPackages[dep.name]!;
        if (!toUpgrade.contains(dep.name)) {
          // If we're not trying to upgrade this package, or it wasn't in the
          // resolution somehow, then we ignore it.
          continue;
        }

        // Skip [dep] if it has a dependency_override.
        if (entrypoint.workspaceRoot.pubspec.dependencyOverrides
            .containsKey(dep.name)) {
          dependencyOverriddenDeps.add(dep.name);
          continue;
        }

        if (dep.constraint.allowsAll(resolvedPackage.version)) {
          // If constraint allows the resolvable version we found, then there is
          // no need to update the `pubspec.yaml`
          continue;
        }

        (changes[package] ??= {})[dep] = dep.toRef().withConstraint(
              VersionConstraint.compatibleWith(resolvedPackage.version),
            );
      }
    }

    if (_tighten) {
      // Do another solve with the updated constraints to obtain the correct
      // versions to tighten to. This should be fast (everything is cached, and
      // no backtracking needed) so we don't show a spinner.

      final solveResult = await resolveVersions(
        SolveType.upgrade,
        cache,
        entrypoint.workspaceRoot.transformWorkspace((package) {
          return applyChanges(package.pubspec, changes[package] ?? {});
        }),
      );
      changes = entrypoint.tighten(
        packagesToUpgrade: _packagesToUpgrade,
        existingChanges: changes,
        packageVersions: solveResult.packages,
      );
    }

    // When doing '--majorVersions' for specific packages we try to update other
    // packages as little as possible to make a focused change (SolveType.get).
    //
    // But without a specific package we want to get as many non-major updates
    // as possible (SolveType.upgrade).
    final solveType =
        _packagesToUpgrade.isEmpty ? SolveType.upgrade : SolveType.get;

    entrypoint.applyChanges(changes, _dryRun);
    await entrypoint.withUpdatedRootPubspecs({
      for (final MapEntry(key: package, value: changesForPackage)
          in changes.entries)
        package: applyChanges(package.pubspec, changesForPackage),
    }).acquireDependencies(
      solveType,
      dryRun: _dryRun,
      precompile: !_dryRun && _precompile,
    );

    // If any of the packages to upgrade are dependency overrides, then we
    // show a warning.
    final toUpgradeOverrides = toUpgrade
        .where(entrypoint.workspaceRoot.allOverridesInWorkspace.containsKey);
    if (toUpgradeOverrides.isNotEmpty) {
      log.warning(
        'Warning: dependency_overrides prevents upgrades for: '
        '${toUpgradeOverrides.join(', ')}',
      );
    }

    _showOfflineWarning();
  }

  Pubspec applyChanges(
    Pubspec original,
    Map<PackageRange, PackageRange> changes,
  ) {
    final dependencies = {...original.dependencies};
    final devDependencies = {...original.devDependencies};

    for (final change in changes.values) {
      if (dependencies[change.name] != null) {
        dependencies[change.name] = change;
      } else {
        devDependencies[change.name] = change;
      }
    }
    return original.copyWith(
      dependencies: dependencies.values,
      devDependencies: devDependencies.values,
    );
  }

  void _showOfflineWarning() {
    if (isOffline) {
      log.warning('Warning: Upgrading when offline may not update you to the '
          'latest versions of your dependencies.');
    }
  }
}
