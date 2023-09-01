// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
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
import '../sdk.dart';
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
          'Running `upgrade --major-versions` only in `${entrypoint.rootDir}`. Run `$topLevelProgram pub upgrade --major-versions --directory example/` separately.',
        );
      }
      await _runUpgradeMajorVersions();
    } else {
      await _runUpgrade(entrypoint);
      if (_tighten) {
        final changes = tighten(
          entrypoint.root.pubspec,
          entrypoint.lockFile.packages.values.toList(),
        );
        if (!_dryRun) {
          final newPubspecText = _updatePubspec(changes);

          if (changes.isNotEmpty) {
            writeTextFile(entrypoint.pubspecPath, newPubspecText);
          }
        }
        _outputChangeSummary(changes);
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
      analytics: analytics,
    );

    _showOfflineWarning();
  }

  /// Returns a list of changes to constraints in [pubspec] updated them to
  ///  have their lower bound match the version in [packages].
  ///
  /// The return value is a mapping from the original package range to the updated.
  ///
  /// If packages to update where given in [_packagesToUpgrade], only those are
  /// tightened. Otherwise all packages are tightened.
  ///
  /// If a dependency has already been updated in [existingChanges], the update
  /// will apply on top of that change (eg. preserving the new upper bound).
  Map<PackageRange, PackageRange> tighten(
    Pubspec pubspec,
    List<PackageId> packages, {
    Map<PackageRange, PackageRange> existingChanges = const {},
  }) {
    final result = {...existingChanges};
    if (argResults.flag('example') && entrypoint.example != null) {
      log.warning(
        'Running `upgrade --tighten` only in `${entrypoint.rootDir}`. Run `$topLevelProgram pub upgrade --tighten --directory example/` separately.',
      );
    }
    final toTighten = _packagesToUpgrade.isEmpty
        ? [
            ...pubspec.dependencies.values,
            ...pubspec.devDependencies.values,
          ]
        : [
            for (final name in _packagesToUpgrade)
              pubspec.dependencies[name] ?? pubspec.devDependencies[name],
          ].whereNotNull();
    for (final range in toTighten) {
      final constraint = (result[range] ?? range).constraint;
      final resolvedVersion =
          packages.firstWhere((p) => p.name == range.name).version;
      if (range.source is HostedSource && constraint.isAny) {
        result[range] = range
            .toRef()
            .withConstraint(VersionConstraint.compatibleWith(resolvedVersion));
      } else if (constraint is VersionRange) {
        final min = constraint.min;
        if (min != null && min < resolvedVersion) {
          result[range] = range.toRef().withConstraint(
                VersionRange(
                  min: resolvedVersion,
                  max: constraint.max,
                  includeMin: true,
                  includeMax: constraint.includeMax,
                ).asCompatibleWithIfPossible(),
              );
        }
      }
    }
    return result;
  }

  /// Return names of packages to be upgraded, and throws [UsageException] if
  /// any package names not in the direct dependencies or dev_dependencies are given.
  ///
  /// This assumes that either `--major-versions` or `--null-safety` was passed.
  List<String> _directDependenciesToUpgrade() {
    assert(_upgradeMajorVersions);

    final directDeps = [
      ...entrypoint.root.pubspec.dependencies.keys,
      ...entrypoint.root.pubspec.devDependencies.keys,
    ];
    final toUpgrade =
        _packagesToUpgrade.isEmpty ? directDeps : _packagesToUpgrade;

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
    var changes = <PackageRange, PackageRange>{};
    final declaredHostedDependencies = [
      ...entrypoint.root.pubspec.dependencies.values,
      ...entrypoint.root.pubspec.devDependencies.values,
    ].where((dep) => dep.source is HostedSource);
    for (final dep in declaredHostedDependencies) {
      final resolvedPackage = resolvedPackages[dep.name]!;
      if (!toUpgrade.contains(dep.name)) {
        // If we're not trying to upgrade this package, or it wasn't in the
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
    var newPubspecText = _updatePubspec(changes);
    if (_tighten) {
      // Do another solve with the updated constraints to obtain the correct
      // versions to tighten to. This should be fast (everything is cached, and
      // no backtracking needed) so we don't show a spinner.

      final solveResult = await resolveVersions(
        SolveType.upgrade,
        cache,
        Package.inMemory(_updatedPubspec(newPubspecText, entrypoint)),
      );
      changes = tighten(
        entrypoint.root.pubspec,
        solveResult.packages,
        existingChanges: changes,
      );
      newPubspecText = _updatePubspec(changes);
    }

    // When doing '--majorVersions' for specific packages we try to update other
    // packages as little as possible to make a focused change (SolveType.get).
    //
    // But without a specific package we want to get as many non-major updates
    // as possible (SolveType.upgrade).
    final solveType =
        _packagesToUpgrade.isEmpty ? SolveType.upgrade : SolveType.get;

    if (!_dryRun) {
      if (changes.isNotEmpty) {
        writeTextFile(entrypoint.pubspecPath, newPubspecText);
      }
    }

    await entrypoint
        .withPubspec(_updatedPubspec(newPubspecText, entrypoint))
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

  Pubspec _updatedPubspec(String contents, Entrypoint entrypoint) {
    String? overridesFileContents;
    final overridesPath =
        p.join(entrypoint.rootDir, Pubspec.pubspecOverridesFilename);
    try {
      overridesFileContents = readTextFile(overridesPath);
    } on IOException {
      overridesFileContents = null;
    }
    return Pubspec.parse(
      contents,
      cache.sources,
      location: Uri.parse(entrypoint.pubspecPath),
      overridesFileContents: overridesFileContents,
      overridesLocation: Uri.file(overridesPath),
    );
  }

  /// Updates `pubspec.yaml` with given [changes].
  String _updatePubspec(
    Map<PackageRange, PackageRange> changes,
  ) {
    ArgumentError.checkNotNull(changes, 'changes');
    final yamlEditor = YamlEditor(readTextFile(entrypoint.pubspecPath));
    final deps = entrypoint.root.pubspec.dependencies.keys;

    for (final change in changes.values) {
      final section =
          deps.contains(change.name) ? 'dependencies' : 'dev_dependencies';
      yamlEditor.update(
        [section, change.name],
        pubspecDescription(change, cache, entrypoint),
      );
    }
    return yamlEditor.toString();
  }

  /// Outputs a summary of changes made to `pubspec.yaml`.
  void _outputChangeSummary(Map<PackageRange, PackageRange> changes) {
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
