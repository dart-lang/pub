// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:args/command_runner.dart';
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
import '../solver/version_solver.dart';
import '../utils.dart';

/// Handles the `upgrade` pub command.
class UpgradeCommand extends PubCommand {
  @override
  String get name => 'upgrade';
  @override
  String get description =>
      "Upgrade the current package's dependencies to latest versions.";
  @override
  String get argumentsDescription => '[dependencies[:latest|:resolvable]...]';
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
      'unlock-transitive',
      help:
          'Also upgrades the transitive dependencies '
          'of the listed [dependencies]',
      negatable: false,
    );

    argParser.addFlag(
      'major-versions',
      help:
          'Upgrades packages to their latest resolvable versions, '
          'and updates pubspec.yaml.',
      negatable: false,
    );

    argParser.addFlag(
      'example',
      defaultsTo: true,
      help: 'Also run in `example/` (if it exists).',
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

  late final Future<List<String>> _packagesToUpgrade =
      _computePackagesToUpgrade();

  late final List<_UpgradeTarget> _upgradeTargets =
      argResults.rest.map(_parseUpgradeTarget).toList();

  late final Future<List<ConstraintAndCause>?> _additionalConstraints =
      _upgradeTargetConstraints();

  late final Future<Map<String, PackageId>> _latestResolvablePackages =
      _computeLatestResolvablePackages();

  /// List of package names to upgrade, if empty then upgrade all packages.
  ///
  /// This allows the user to specify list of names that they want the
  /// upgrade command to affect.
  Future<List<String>> _computePackagesToUpgrade() async {
    if (argResults.flag('unlock-transitive')) {
      final graph = await entrypoint.packageGraph;
      return _upgradeTargets
          .expand(
            (target) => graph
                .transitiveDependencies(
                  target.name,
                  followDevDependenciesFromPackage: true,
                )
                .map((p) => p.name),
          )
          .toSet()
          .toList();
    } else {
      return _upgradeTargets.map((target) => target.name).toList();
    }
  }

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
    if (_upgradeTargets.any((target) => target.kind != null)) {
      if (_upgradeMajorVersions) {
        usageException(
          'Cannot use `:latest` or `:resolvable` with `--major-versions`.',
        );
      }
      if (_tighten) {
        usageException(
          'Cannot use `:latest` or `:resolvable` with `--tighten`.',
        );
      }
    }

    if (_upgradeMajorVersions) {
      if (argResults.flag('example')) {
        for (final example in entrypoint.examples) {
          log.warning(
            'Running `upgrade --major-versions` only in '
            '`${entrypoint.workspaceRoot.dir}`. '
            'Run `$topLevelProgram pub upgrade --major-versions '
            '--directory ${example.workspaceRoot.presentationDir}` separately.',
          );
        }
      }
      await _runUpgradeMajorVersions();
    } else {
      await _runUpgrade(entrypoint);
      if (_tighten) {
        if (argResults.flag('example')) {
          for (final example in entrypoint.examples) {
            log.warning(
              'Running `upgrade --tighten` only in '
              '`${entrypoint.workspaceRoot.dir}`. '
              'Run `$topLevelProgram pub upgrade --tighten '
              '--directory ${example.workspaceRoot.presentationDir}` '
              'separately.',
            );
          }
        }
        final changes = entrypoint.tighten(
          packagesToUpgrade: await _packagesToUpgrade,
        );
        entrypoint.applyChanges(changes, _dryRun);
      }
    }
    if (argResults.flag('example')) {
      for (final example in entrypoint.examples) {
        await _runUpgrade(example, onlySummary: true);
      }
    }
  }

  Future<void> _runUpgrade(Entrypoint e, {bool onlySummary = false}) async {
    await e.acquireDependencies(
      SolveType.upgrade,
      unlock: await _packagesToUpgrade,
      additionalConstraints: await _additionalConstraints,
      dryRun: _dryRun,
      precompile: _precompile,
      summaryOnly: onlySummary,
    );

    _showOfflineWarning();
  }

  Future<List<ConstraintAndCause>?> _upgradeTargetConstraints() async {
    final constraintFutures = <Future<ConstraintAndCause>>[];
    for (final target in _upgradeTargets) {
      final kind = target.kind;
      if (kind == null) continue;

      constraintFutures.add(
        (() async {
          final targetPackage = switch (kind) {
            _UpgradeTargetKind.latest => await _latest(target.name),
            _UpgradeTargetKind.resolvable => await _latestResolvable(
              target.name,
            ),
          };
          return ConstraintAndCause(
            targetPackage.toRange(),
            '${targetPackage.name} ${targetPackage.version} was requested by '
            '`$topLevelProgram pub upgrade ${target.argument}`.',
          );
        })(),
      );
    }
    final constraints = await Future.wait(constraintFutures);
    return constraints.isEmpty ? null : constraints;
  }

  Future<Map<String, PackageId>> _computeLatestResolvablePackages() async {
    final solveResult = await log.spinner('Resolving dependencies', () async {
      return await resolveVersions(
        SolveType.upgrade,
        cache,
        entrypoint.workspaceRoot.transformWorkspace(
          (package) => stripVersionBounds(package.pubspec),
        ),
      );
    }, condition: _shouldShowSpinner);
    return {for (final package in solveResult.packages) package.name: package};
  }

  Future<PackageId> _latestResolvable(String package) async {
    if (_packageRef(package) == null) {
      dataError('Package `$package` is not in the current resolution.');
    }
    final latestResolvable = (await _latestResolvablePackages)[package];
    if (latestResolvable == null) {
      dataError(
        'Package `$package` is not in the latest resolvable resolution.',
      );
    }
    return latestResolvable;
  }

  Future<PackageId> _latest(String package) async {
    final ref = _packageRef(package);
    if (ref == null) {
      dataError('Package `$package` is not in the current resolution.');
    }
    final current = entrypoint.lockFile.packages[package];
    final latest = await cache.getLatest(ref, version: current?.version);
    if (latest == null) {
      dataError('Could not find package `$package`.');
    }
    return latest;
  }

  PackageRef? _packageRef(String package) {
    final current = entrypoint.lockFile.packages[package];
    if (current != null) return current.toRef();

    for (final workspacePackage
        in entrypoint.workspaceRoot.transitiveWorkspace) {
      final dependency = workspacePackage.dependencies[package];
      if (dependency != null) return dependency.toRef();
      final devDependency = workspacePackage.devDependencies[package];
      if (devDependency != null) return devDependency.toRef();
    }
    return null;
  }

  _UpgradeTarget _parseUpgradeTarget(String argument) {
    final parts = argument.split(':');
    if (parts.length > 2) {
      usageException('Could not parse `$argument`.');
    }

    final package = parts.first;
    if (!packageNameRegExp.hasMatch(package)) {
      usageException('Not a valid package name: "$package"');
    }

    if (parts.length == 1) {
      return _UpgradeTarget(argument, package, null);
    }

    final suffix = parts.last;
    final kind = switch (suffix) {
      'latest' => _UpgradeTargetKind.latest,
      'resolvable' => _UpgradeTargetKind.resolvable,
      _ => null,
    };
    if (kind == null) {
      usageException(
        'Unknown upgrade target `$argument`. Use `<package>`, '
        '`<package>:latest`, or `<package>:resolvable`.',
      );
    }
    return _UpgradeTarget(argument, package, kind);
  }

  /// Return names of packages to be upgraded, and throws [UsageException] if
  /// any package names not in the direct dependencies or dev_dependencies are
  /// given.
  ///
  /// This assumes that `--major-versions` was passed.
  Future<List<String>> _directDependenciesToUpgrade() async {
    assert(_upgradeMajorVersions);

    final directDeps =
        {
          for (final package
              in entrypoint.workspaceRoot.transitiveWorkspace) ...[
            ...package.dependencies.keys,
            ...package.devDependencies.keys,
          ],
        }.toList();
    final packagesToUpgrade = await _packagesToUpgrade;
    final toUpgrade =
        packagesToUpgrade.isEmpty ? directDeps : packagesToUpgrade;

    // Check that all package names in upgradeOnly are direct-dependencies
    final notInDeps = toUpgrade.where((n) => !directDeps.contains(n));
    if (argResults.rest.any(notInDeps.contains)) {
      usageException('''
Dependencies specified in `$topLevelProgram pub upgrade --major-versions <dependencies>` must
be direct 'dependencies' or 'dev_dependencies', following packages are not:
 - ${notInDeps.join('\n - ')}

''');
    }

    return toUpgrade;
  }

  Future<void> _runUpgradeMajorVersions() async {
    final toUpgrade = await _directDependenciesToUpgrade();
    final resolvedPackages = await _latestResolvablePackages;
    final dependencyOverriddenDeps = <String>[];
    // Changes to be made to `pubspec.yaml` of each package.
    // Mapping from original to changed value.
    var changes = <Package, Map<PackageRange, PackageRange>>{};
    for (final package in entrypoint.workspaceRoot.transitiveWorkspace) {
      final declaredUpgradableDependencies = [
        ...package.dependencies.values,
        ...package.devDependencies.values,
      ].where((dep) => dep.description.hasMultipleVersions);
      for (final dep in declaredUpgradableDependencies) {
        final resolvedPackage = resolvedPackages[dep.name]!;
        if (!toUpgrade.contains(dep.name)) {
          // If we're not trying to upgrade this package, or it wasn't in the
          // resolution somehow, then we ignore it.
          continue;
        }

        // Skip [dep] if it has a dependency_override.
        if (entrypoint.workspaceRoot.pubspec.dependencyOverrides.containsKey(
          dep.name,
        )) {
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
        packagesToUpgrade: await _packagesToUpgrade,
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
        (await _packagesToUpgrade).isEmpty ? SolveType.upgrade : SolveType.get;

    entrypoint.applyChanges(changes, _dryRun);
    await entrypoint
        .withUpdatedRootPubspecs({
          for (final MapEntry(key: package, value: changesForPackage)
              in changes.entries)
            package: applyChanges(package.pubspec, changesForPackage),
        })
        .acquireDependencies(
          solveType,
          dryRun: _dryRun,
          precompile: !_dryRun && _precompile,
          unlock: await _packagesToUpgrade,
        );

    // If any of the packages to upgrade are dependency overrides, then we
    // show a warning.
    final toUpgradeOverrides = toUpgrade.where(
      entrypoint.workspaceRoot.allOverridesInWorkspace.containsKey,
    );
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
      log.warning(
        'Warning: Upgrading when offline may not update you to the '
        'latest versions of your dependencies.',
      );
    }
  }
}

enum _UpgradeTargetKind { latest, resolvable }

class _UpgradeTarget {
  final String argument;
  final String name;
  final _UpgradeTargetKind? kind;

  _UpgradeTarget(this.argument, this.name, this.kind);
}
