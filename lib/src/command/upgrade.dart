// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:pub_semver/pub_semver.dart';
import 'package:yaml_edit/yaml_edit.dart';

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
  bool get isOffline => asBool(argResults['offline']);

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

  bool get _dryRun => asBool(argResults['dry-run']);

  bool get _precompile => asBool(argResults['precompile']);

  bool get _upgradeNullSafety =>
      asBool(argResults['nullsafety']) || asBool(argResults['null-safety']);

  bool get _upgradeMajorVersions => asBool(argResults['major-versions']);

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
      if (asBool(argResults['example'], whenNull: true) &&
          entrypoint.example != null) {
        log.warning(
          'Running `upgrade --major-versions` only in `${entrypoint.rootDir}`. Run `$topLevelProgram pub upgrade --major-versions --directory example/` separately.',
        );
      }
      await _runUpgradeMajorVersions();
    } else {
      await _runUpgrade(entrypoint);
    }
    if (asBool(argResults['example'], whenNull: true) &&
        entrypoint.example != null) {
      // Reload the entrypoint to ensure we pick up potential changes that has
      // been made.
      final exampleEntrypoint = Entrypoint(directory, cache).example!;
      await _runUpgrade(exampleEntrypoint, onlySummary: true);
    }
  }

  Future<void> _runUpgrade(Entrypoint e, {bool onlySummary = false}) async {
    await e.acquireDependencies(
      SolveType.upgrade,
      unlock: argResults.rest,
      dryRun: _dryRun,
      precompile: _precompile,
      summaryOnly: onlySummary,
      analytics: analytics,
    );
    _showOfflineWarning();
  }

  /// Return names of packages to be upgraded, and throws [UsageException] if
  /// any package names not in the direct dependencies or dev_dependencies are given.
  ///
  /// This assumes that either `--major-versions` or `--null-safety` was passed.
  List<String> _directDependenciesToUpgrade() {
    assert(_upgradeMajorVersions);

    final directDeps = [
      ...entrypoint.root.pubspec.dependencies.keys,
      ...entrypoint.root.pubspec.devDependencies.keys
    ];
    final toUpgrade = argResults.rest.isEmpty ? directDeps : argResults.rest;

    // Check that all package names in upgradeOnly are direct-dependencies
    final notInDeps = toUpgrade.where((n) => !directDeps.contains(n));
    if (toUpgrade.any(notInDeps.contains)) {
      var modeFlag = '';
      if (_upgradeMajorVersions) {
        modeFlag = '--major-versions';
      }

      usageException('''
Dependencies specified in `$topLevelProgram pub upgrade $modeFlag <dependencies>` must
be direct 'dependencies' or 'dev_dependencies', following packages are not:
 - ${notInDeps.join('\n - ')}

''');
    }

    return toUpgrade;
  }

  Future<void> _runUpgradeMajorVersions() async {
    final toUpgrade = _directDependenciesToUpgrade();

    final resolvablePubspec = stripVersionBounds(
      entrypoint.root.pubspec,
      stripOnly: toUpgrade,
    );

    // Solve [resolvablePubspec] in-memory and consolidate the resolved
    // versions of the packages into a map for quick searching.
    final resolvedPackages = <String, PackageId>{};
    final solveResult = await log.spinner(
      'Resolving dependencies',
      () async {
        return await resolveVersions(
          SolveType.upgrade,
          cache,
          Package.inMemory(resolvablePubspec),
        );
      },
      condition: _shouldShowSpinner,
    );
    for (final resolvedPackage in solveResult.packages) {
      resolvedPackages[resolvedPackage.name] = resolvedPackage;
    }

    // Changes to be made to `pubspec.yaml`.
    // Mapping from original to changed value.
    final changes = <PackageRange, PackageRange>{};
    final declaredHostedDependencies = [
      ...entrypoint.root.pubspec.dependencies.values,
      ...entrypoint.root.pubspec.devDependencies.values,
    ].where((dep) => dep.source is HostedSource);
    for (final dep in declaredHostedDependencies) {
      final resolvedPackage = resolvedPackages[dep.name]!;
      if (!toUpgrade.contains(dep.name)) {
        // If we're not to upgrade this package, or it wasn't in the
        // resolution somehow, then we ignore it.
        continue;
      }

      // Skip [dep] if it has a dependency_override.
      if (entrypoint.root.dependencyOverrides.containsKey(dep.name)) {
        continue;
      }

      if (dep.constraint.allowsAll(resolvedPackage.version)) {
        // If constraint allows the resolvable version we found, then there is
        // no need to update the `pubspec.yaml`
        continue;
      }

      changes[dep] = dep.toRef().withConstraint(
            VersionConstraint.compatibleWith(
              resolvedPackage.version,
            ),
          );
    }
    final newPubspecText = _updatePubspec(changes);

    // When doing '--majorVersions' for specific packages we try to update other
    // packages as little as possible to make a focused change (SolveType.get).
    //
    // But without a specific package we want to get as many non-major updates
    // as possible (SolveType.upgrade).
    final solveType =
        argResults.rest.isEmpty ? SolveType.upgrade : SolveType.get;

    if (!_dryRun) {
      if (changes.isNotEmpty) {
        writeTextFile(entrypoint.pubspecPath, newPubspecText);
      }
    }

    await entrypoint
        .withPubspec(
          Pubspec.parse(
            newPubspecText,
            cache.sources,
            location: Uri.parse(entrypoint.pubspecPath),
          ),
        )
        .acquireDependencies(
          solveType,
          dryRun: _dryRun,
          precompile: !_dryRun && _precompile,
          analytics: _dryRun ? null : analytics, // No analytics for dry-run
        );

    _outputChangeSummary(changes);

    // If any of the packages to upgrade are dependency overrides, then we
    // show a warning.
    final toUpgradeOverrides =
        toUpgrade.where(entrypoint.root.dependencyOverrides.containsKey);
    if (toUpgradeOverrides.isNotEmpty) {
      log.warning(
        'Warning: dependency_overrides prevents upgrades for: '
        '${toUpgradeOverrides.join(', ')}',
      );
    }

    _showOfflineWarning();
  }

  /// Updates `pubspec.yaml` with given [changes].
  String _updatePubspec(
    Map<PackageRange, PackageRange> changes,
  ) {
    ArgumentError.checkNotNull(changes, 'changes');

    final yamlEditor = YamlEditor(readTextFile(entrypoint.pubspecPath));
    final deps = entrypoint.root.pubspec.dependencies.keys;
    final devDeps = entrypoint.root.pubspec.devDependencies.keys;

    for (final change in changes.values) {
      if (deps.contains(change.name)) {
        yamlEditor.update(
          ['dependencies', change.name],
          // TODO(jonasfj): Fix support for third-party pub servers.
          change.constraint.toString(),
        );
      } else if (devDeps.contains(change.name)) {
        yamlEditor.update(
          ['dev_dependencies', change.name],
          // TODO: Fix support for third-party pub servers
          change.constraint.toString(),
        );
      }
    }
    return yamlEditor.toString();
  }

  /// Outputs a summary of changes made to `pubspec.yaml`.
  void _outputChangeSummary(
    Map<PackageRange, PackageRange> changes,
  ) {
    ArgumentError.checkNotNull(changes, 'changes');

    if (changes.isEmpty) {
      final wouldBe = _dryRun ? 'would be made to' : 'to';
      log.message('\nNo changes $wouldBe pubspec.yaml!');
    } else {
      final changed = _dryRun ? 'Would change' : 'Changed';
      log.message('\n$changed ${changes.length} '
          '${pluralize('constraint', changes.length)} in pubspec.yaml:');
      changes.forEach((from, to) {
        log.message('  ${from.name}: ${from.constraint} -> ${to.constraint}');
      });
    }
  }

  void _showOfflineWarning() {
    if (isOffline) {
      log.warning('Warning: Upgrading when offline may not update you to the '
          'latest versions of your dependencies.');
    }
  }
}
