// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:yaml_edit/yaml_edit.dart';

import '../command.dart';
import '../entrypoint.dart';
import '../io.dart';
import '../log.dart' as log;
import '../package.dart';
import '../package_name.dart';
import '../pubspec.dart';
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
            'and updates pubspec.yaml');
  }

  @override
  Future run() async {
    if (argResults.wasParsed('packages-dir')) {
      log.warning(log.yellow(
          'The --packages-dir flag is no longer used and does nothing.'));
    }

    if (argResults.wasParsed('breaking')) {
      final useLatest = argResults.rest;

      final rootPubspec = entrypoint.root.pubspec;
      final resolvablePubspec =
          _stripVersionConstraints(rootPubspec, useLatest: useLatest);

      Map<String, PackageId> resolvablePackages;
      await log.spinner('Resolving', () async {
        resolvablePackages = await _tryResolve(resolvablePubspec);
      }, condition: _shouldShowSpinner);

      final dependencyChanges = <PackageRange, PackageId>{};
      final allDependencies = [
        ...rootPubspec.dependencies.values,
        ...rootPubspec.devDependencies.values
      ];

      for (var package in allDependencies) {
        final resolvedPackage = resolvablePackages[package.name];

        if (resolvedPackage != null &&
            !package.constraint.allows(resolvedPackage.version) &&
            package.source is HostedSource) {
          dependencyChanges[package] = resolvedPackage;
        }
      }

      if (!argResults['dry-run']) {
        await _writeToPubspec(dependencyChanges);
        await Entrypoint.current(cache).acquireDependencies(SolveType.UPGRADE);
      }

      _outputHuman(dependencyChanges, argResults['dry-run']);
    } else {
      await entrypoint.acquireDependencies(SolveType.UPGRADE,
          useLatest: argResults.rest,
          dryRun: argResults['dry-run'],
          precompile: argResults['precompile']);
    }

    if (isOffline) {
      log.warning('Warning: Upgrading when offline may not update you to the '
          'latest versions of your dependencies.');
    }
  }

  /// Writes the differences between [resolvedPackages] and the current
  /// dependencies to the pubspec file.
  Future<void> _writeToPubspec(
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

  /// Try to solve [pubspec] return [PackageId]'s in the resolution or `null`.
  Future<Map<String, PackageId>> _tryResolve(Pubspec pubspec) async {
    try {
      final resolvedPackages = (await resolveVersions(
        SolveType.UPGRADE,
        cache,
        Package.inMemory(pubspec),
      ))
          .packages;

      final result = <String, PackageId>{};

      for (final resolvedPackage in resolvedPackages) {
        result[resolvedPackage.name] = resolvedPackage;
      }

      return result;
    } on SolveFailure {
      return <String, PackageId>{};
    }
  }
}

/// Outputs a summary of changes that will be made
void _outputHuman(
    Map<PackageRange, PackageId> dependencyChanges, bool isDryRun) {
  ArgumentError.checkNotNull(dependencyChanges, 'dependencyChanges');

  if (dependencyChanges.isEmpty) {
    log.message('No breaking changes detected!');
  } else {
    if (isDryRun) {
      log.message(
          '${dependencyChanges.length} breaking change(s) would have been made:');
    } else {
      log.message(
          '${dependencyChanges.length} breaking change(s) have been made:');
    }

    for (final change in dependencyChanges.entries) {
      final initialPackage = change.key;
      final finalPackage = change.value;

      log.message('${initialPackage.name}: ${initialPackage.constraint} -> '
          '^${finalPackage.version}');
    }
  }
}

/// Returns new pubspec with the same dependencies as [original] but with no
/// version constraints on hosted packages.
Pubspec _stripVersionConstraints(Pubspec original, {List<String> useLatest}) {
  useLatest ??= [];

  List<PackageRange> _unconstrained(Map<String, PackageRange> constrained,
      {List<String> useLatest}) {
    final result = <PackageRange>[];

    for (final name in constrained.keys) {
      final packageRange = constrained[name];
      var unconstrainedRange = packageRange;
      if (packageRange.source is HostedSource &&
          (useLatest.isEmpty || useLatest.contains(packageRange.name))) {
        unconstrainedRange = PackageRange(
            packageRange.name,
            packageRange.source,
            VersionConstraint.any,
            packageRange.description,
            features: packageRange.features);
      }
      result.add(unconstrainedRange);
    }

    return result;
  }

  return Pubspec(
    original.name,
    version: original.version,
    sdkConstraints: original.sdkConstraints,
    dependencies: _unconstrained(original.dependencies, useLatest: useLatest),
    devDependencies:
        _unconstrained(original.devDependencies, useLatest: useLatest),
    dependencyOverrides: original.dependencyOverrides.values,
  );
}
