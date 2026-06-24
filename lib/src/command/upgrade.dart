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
      "Upgrade the current package's dependencies to latest versions.\n"
      '\n'
      'Append `@<constraint>` to a dependency to require a version '
      'constraint.\n'
      '\n'
      'Append `@latest` to a dependency to require the latest available '
      'version.\n'
      '\n'
      'Append `@resolvable` to require the newest version resolvable with the '
      'rest of\n'
      'the dependencies.';
  @override
  String get argumentsDescription =>
      '[dependencies[@<constraint>|@latest|@resolvable]...]';
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

  late final Future<List<String>> _rootPackagesToUpgrade =
      _computePackagesToUpgrade(entrypoint);

  late final List<_UpgradeTarget> _upgradeTargets =
      argResults.rest.map(_parseUpgradeTarget).toList();

  /// List of package names to upgrade, if empty then upgrade all packages.
  ///
  /// This allows the user to specify list of names that they want the
  /// upgrade command to affect.
  Future<List<String>> _packagesToUpgrade(Entrypoint e) {
    if (identical(e, entrypoint)) return _rootPackagesToUpgrade;
    return _computePackagesToUpgrade(e);
  }

  Future<List<String>> _computePackagesToUpgrade(Entrypoint e) async {
    if (argResults.flag('unlock-transitive')) {
      final graph = await e.packageGraph;
      final packagesToUnlock =
          _upgradeTargets
              .expand(
                (target) =>
                    graph.packages.containsKey(target.name)
                        ? graph
                            .transitiveDependencies(
                              target.name,
                              followDevDependenciesFromPackage: true,
                            )
                            .map((p) => p.name)
                        : const <String>[],
              )
              .toSet()
              .toList();
      if (_upgradeTargets.isNotEmpty && packagesToUnlock.isEmpty) {
        return _upgradeTargets.map((target) => target.name).toList();
      }
      return packagesToUnlock;
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
    final hasUpgradeTargetConstraints = _upgradeTargets.any(
      (target) => target.kind != null,
    );

    if (hasUpgradeTargetConstraints ||
        (argResults.flag('unlock-transitive') && _upgradeTargets.isNotEmpty)) {
      _validateUpgradeTargetEntrypoints(
        validatePlainTargets: argResults.flag('unlock-transitive'),
      );
      _validateUpgradeTargetConstraintsOverlap();
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
          packagesToUpgrade: await _rootPackagesToUpgrade,
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
      unlock: await _packagesToUpgrade(e),
      additionalConstraints: await _upgradeTargetConstraints(e),
      dryRun: _dryRun,
      precompile: _precompile,
      summaryOnly: onlySummary,
    );

    _showOfflineWarning();
  }

  List<Entrypoint> get _entrypointsToUpgrade => [
    entrypoint,
    if (argResults.flag('example')) ...entrypoint.examples,
  ];

  void _validateUpgradeTargetEntrypoints({required bool validatePlainTargets}) {
    for (final target in _upgradeTargets) {
      if (target.kind == null && !validatePlainTargets) continue;
      if (_entrypointsToUpgrade.any(
        (e) => _packageRef(e, target.name) != null,
      )) {
        continue;
      }
      final entrypoints =
          argResults.flag('example')
              ? 'the root package or any examples'
              : 'the root package';
      dataError(
        'Package `${target.name}` is not in the current resolution. '
        'It was not found in $entrypoints.',
      );
    }
  }

  void _validateUpgradeTargetConstraintsOverlap() {
    if (_upgradeMajorVersions) return;

    for (final target in _upgradeTargets) {
      if (target.kind != _UpgradeTargetKind.constraint) continue;
      for (final entrypoint in _entrypointsToUpgrade) {
        _validateUpgradeTargetConstraintOverlap(entrypoint, target);
      }
    }
  }

  void _validateUpgradeTargetConstraintOverlap(
    Entrypoint e,
    _UpgradeTarget target,
  ) {
    final targetConstraint = target.constraint!;
    var hasOverride = false;
    for (final workspacePackage in e.workspaceRoot.transitiveWorkspace) {
      final override =
          workspacePackage.pubspec.dependencyOverrides[target.name];
      if (override == null) continue;
      hasOverride = true;
      if (!override.constraint.allowsAny(targetConstraint)) {
        final pubspecPath =
            workspacePackage.pubspec.dependencyOverridesFromOverridesFile
                ? workspacePackage.pubspecOverridesPath
                : workspacePackage.pubspecPath;
        dataError(
          'The requested constraint `$targetConstraint` for `${target.name}` '
          'does not overlap with the dependency override constraint '
          '`${override.constraint}` in `$pubspecPath`.\n'
          'Update or remove the dependency override before retrying.',
        );
      }
    }
    if (hasOverride) return;

    for (final workspacePackage in e.workspaceRoot.transitiveWorkspace) {
      final dependency = workspacePackage.dependencies[target.name];
      final devDependency = workspacePackage.devDependencies[target.name];
      final declaredConstraint =
          dependency?.constraint ?? devDependency?.constraint;
      if (declaredConstraint == null ||
          declaredConstraint.allowsAny(targetConstraint)) {
        continue;
      }
      dataError(
        'The requested constraint `$targetConstraint` for `${target.name}` '
        'does not overlap with the current constraint `$declaredConstraint` '
        'in `${workspacePackage.pubspecPath}`.\n'
        'To update the constraint, run '
        '`${_suggestedMajorVersionsCommand(e, target)}`.',
      );
    }
  }

  String _suggestedMajorVersionsCommand(Entrypoint e, _UpgradeTarget target) {
    final directoryOption =
        identical(e, entrypoint) ? directory : e.workspaceRoot.dir;
    final disableExamples = e.examples.isNotEmpty;
    return [
      topLevelProgram,
      'pub',
      'upgrade',
      '--major-versions',
      if (_tighten) '--tighten',
      if (argResults.flag('unlock-transitive')) '--unlock-transitive',
      if (disableExamples) '--no-example',
      if (directoryOption != '.') ...['--directory', directoryOption],
      target.argument,
    ].map(escapeShellArgument).join(' ');
  }

  Future<List<ConstraintAndCause>?> _upgradeTargetConstraints(
    Entrypoint e,
  ) async {
    final constraints = <ConstraintAndCause>[];
    final resolvableTargets = <_UpgradeTarget>[];

    ConstraintAndCause constraintAndCause(
      PackageRange targetRange,
      VersionConstraint targetConstraint,
      String argument,
    ) {
      return ConstraintAndCause(
        targetRange,
        '${targetRange.name} $targetConstraint was requested by '
        '`$topLevelProgram pub upgrade $argument`.',
      );
    }

    for (final target in _upgradeTargets) {
      final kind = target.kind;
      if (kind == null) continue;
      final ref = _packageRef(e, target.name);
      if (ref == null) continue;

      switch (kind) {
        case _UpgradeTargetKind.latest:
          final targetPackage = await _latest(e, target.name, ref);
          constraints.add(
            constraintAndCause(
              targetPackage.toRange(),
              targetPackage.version,
              target.argument,
            ),
          );
        case _UpgradeTargetKind.resolvable:
          resolvableTargets.add(target);
        case _UpgradeTargetKind.constraint:
          final targetConstraint = target.constraint!;
          constraints.add(
            constraintAndCause(
              ref.withConstraint(targetConstraint),
              targetConstraint,
              target.argument,
            ),
          );
      }
    }

    if (resolvableTargets.isNotEmpty) {
      final packages = await _computeLatestResolvablePackages(
        e,
        additionalConstraints:
            constraints.isEmpty
                ? null
                : List<ConstraintAndCause>.of(constraints),
      );
      for (final target in resolvableTargets) {
        final targetPackage = packages[target.name];
        if (targetPackage == null) {
          dataError(
            'Package `${target.name}` is not in the latest resolvable '
            'resolution.',
          );
        }
        constraints.add(
          constraintAndCause(
            targetPackage.toRange(),
            targetPackage.version,
            target.argument,
          ),
        );
      }
    }

    return constraints.isEmpty ? null : constraints;
  }

  Future<Map<String, PackageId>> _computeLatestResolvablePackages(
    Entrypoint e, {
    Iterable<ConstraintAndCause>? additionalConstraints,
  }) async {
    final solveResult = await log.spinner('Resolving dependencies', () async {
      return await resolveVersions(
        SolveType.upgrade,
        cache,
        e.workspaceRoot.transformWorkspace(
          (package) => stripVersionBounds(package.pubspec),
        ),
        additionalConstraints: additionalConstraints,
      );
    }, condition: _shouldShowSpinner);
    return {for (final package in solveResult.packages) package.name: package};
  }

  Future<PackageId> _latest(
    Entrypoint e,
    String package,
    PackageRef ref,
  ) async {
    final current = e.lockFile.packages[package];
    final currentVersionForRef =
        current?.toRef() == ref ? current?.version : null;
    final latest = await cache.getLatest(ref, version: currentVersionForRef);
    if (latest == null) {
      dataError('Could not find package `$package`.');
    }
    return latest;
  }

  PackageRef? _packageRef(Entrypoint e, String package) {
    final override = e.workspaceRoot.allOverridesInWorkspace[package];
    if (override != null) return override.toRef();

    for (final workspacePackage in e.workspaceRoot.transitiveWorkspace) {
      final dependency = workspacePackage.dependencies[package];
      if (dependency != null) return dependency.toRef();
      final devDependency = workspacePackage.devDependencies[package];
      if (devDependency != null) return devDependency.toRef();
    }
    final current = e.lockFile.packages[package];
    if (current != null) return current.toRef();
    return null;
  }

  _UpgradeTarget _parseUpgradeTarget(String argument) {
    final oldStyleParts = argument.split(':');
    if (oldStyleParts.length == 2 &&
        packageNameRegExp.hasMatch(oldStyleParts.first) &&
        (oldStyleParts.last == 'latest' ||
            oldStyleParts.last == 'resolvable')) {
      usageException(
        'Unknown upgrade target `$argument`. Use `<package>`, '
        '`<package>@<constraint>`, `<package>@latest`, or '
        '`<package>@resolvable`.',
      );
    }

    final parts = argument.split('@');
    if (parts.length > 2) {
      usageException(
        'Could not parse upgrade target `$argument`. Use `<package>`, '
        '`<package>@<constraint>`, `<package>@latest`, or '
        '`<package>@resolvable`.',
      );
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
      try {
        return _UpgradeTarget(
          argument,
          package,
          _UpgradeTargetKind.constraint,
          VersionConstraint.parse(suffix),
        );
      } on FormatException catch (_) {
        usageException(
          'Unknown upgrade target `$argument`. Use `<package>`, '
          '`<package>@<constraint>`, `<package>@latest`, or '
          '`<package>@resolvable`.',
        );
      }
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
    final packagesToUpgrade = await _rootPackagesToUpgrade;
    final toUpgrade =
        packagesToUpgrade.isEmpty ? directDeps : packagesToUpgrade;

    // Check that all package names in upgradeOnly are direct-dependencies
    final notInDeps = _upgradeTargets
        .map((target) => target.name)
        .where((n) => !directDeps.contains(n));
    if (notInDeps.isNotEmpty) {
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
    final upgradeTargetConstraints = await _upgradeTargetConstraints(
      entrypoint,
    );
    final resolvedPackages = await _computeLatestResolvablePackages(
      entrypoint,
      additionalConstraints: upgradeTargetConstraints,
    );
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
        additionalConstraints: upgradeTargetConstraints,
      );
      changes = entrypoint.tighten(
        packagesToUpgrade: await _rootPackagesToUpgrade,
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
        (await _rootPackagesToUpgrade).isEmpty
            ? SolveType.upgrade
            : SolveType.get;

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
          unlock: await _rootPackagesToUpgrade,
          additionalConstraints: upgradeTargetConstraints,
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

enum _UpgradeTargetKind { latest, resolvable, constraint }

class _UpgradeTarget {
  final String argument;
  final String name;
  final _UpgradeTargetKind? kind;
  final VersionConstraint? constraint;

  _UpgradeTarget(this.argument, this.name, this.kind, [this.constraint]);
}
