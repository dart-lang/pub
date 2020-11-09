// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:pub_semver/pub_semver.dart';

import '../command.dart';
import '../entrypoint.dart';
import '../exceptions.dart';
import '../io.dart';
import '../log.dart' as log;
import '../null_safety_analysis.dart';
import '../package.dart';
import '../package_name.dart';
import '../pubspec.dart';
import '../solver.dart';
import '../source/hosted.dart';
import '../yaml_edit/editor.dart';

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
  bool get isOffline => argResults['offline'];

  UpgradeCommand() {
    argParser.addFlag('offline',
        help: 'Use cached packages instead of accessing the network.');

    argParser.addFlag('dry-run',
        abbr: 'n',
        negatable: false,
        help: "Report what dependencies would change but don't change any.");

    argParser.addFlag('precompile',
        help: 'Precompile executables in immediate dependencies.');

    argParser.addFlag('nullsafety',
        negatable: false,
        help: 'Upgrade constraints in pubspec.yaml to null-safety versions');

    argParser.addFlag('packages-dir', hide: true);
  }

  /// Avoid showing spinning progress messages when not in a terminal.
  bool get _shouldShowSpinner => stdout.hasTerminal;

  bool get _dryRun => argResults['dry-run'];

  @override
  Future<void> runProtected() async {
    if (argResults.wasParsed('packages-dir')) {
      log.warning(log.yellow(
          'The --packages-dir flag is no longer used and does nothing.'));
    }

    if (argResults['nullsafety']) {
      final upgradeOnly = [
        if (argResults.rest.isNotEmpty)
          ...argResults.rest
        else ...[
          ...entrypoint.root.pubspec.dependencies.keys,
          ...entrypoint.root.pubspec.devDependencies.keys
        ],
      ];

      final nullsafetyPubspec = await _upgradeToNullSafetyConstraints(
        entrypoint.root.pubspec,
        upgradeOnly,
      );

      /// Solve [nullsafetyPubspec] in-memory and consolidate the resolved
      /// versions of the packages into a map for quick searching.
      final resolvedPackages = <String, PackageId>{};
      await log.spinner('Resolving', () async {
        final solveResult = await tryResolveVersions(
          SolveType.UPGRADE,
          cache,
          Package.inMemory(nullsafetyPubspec),
        );
        for (final resolvedPackage in solveResult?.packages ?? []) {
          resolvedPackages[resolvedPackage.name] = resolvedPackage;
        }
      }, condition: _shouldShowSpinner);

      /// List of changes to made to `pubspec.yaml`.
      final changes = <PackageRange, PackageRange>{};
      final declaredHostedDependencies = [
        ...entrypoint.root.pubspec.dependencies.values,
        ...entrypoint.root.pubspec.devDependencies.values,
      ].where((dep) => dep.source is HostedSource);
      for (final dep in declaredHostedDependencies) {
        final resolvedPackage = resolvedPackages[dep.name];
        assert(resolvedPackage != null);
        if (resolvedPackage == null || !upgradeOnly.contains(dep.name)) {
          // If we're not to upgrade this package, or it wasn't in the
          // resolution somehow, then we ignore it.
          continue;
        }

        final constraint = VersionConstraint.compatibleWith(
          resolvedPackage.version,
        );
        if (dep.constraint.allowsAll(constraint) &&
            constraint.allowsAll(dep.constraint)) {
          // If constraint allows the same as the existing constraint then
          // there is no need to changes.
          continue;
        }

        changes[dep] = dep.withConstraint(constraint);
      }

      if (!_dryRun) {
        await _updatePubspec(changes);
      }

      _outputChangeSummary(changes);
    }

    await Entrypoint.current(cache).acquireDependencies(SolveType.UPGRADE,
        useLatest: argResults.rest,
        dryRun: _dryRun,
        precompile: argResults['precompile']);

    if (isOffline) {
      log.warning('Warning: Upgrading when offline may not update you to the '
          'latest versions of your dependencies.');
    }
  }

  /// Updates `pubspec.yaml` with given [changes].
  Future<void> _updatePubspec(
    Map<PackageRange, PackageRange> changes,
  ) async {
    ArgumentError.checkNotNull(changes, 'changes');

    if (changes.isEmpty) return;

    final yamlEditor = YamlEditor(readTextFile(entrypoint.pubspecPath));
    final deps = entrypoint.root.pubspec.dependencies.keys;
    final devDeps = entrypoint.root.pubspec.devDependencies.keys;

    for (final c in changes.values) {
      if (deps.contains(c.name)) {
        yamlEditor.update(
          ['dependencies', c.name],
          // TODO: Fix support for third-party pub servers
          c.constraint.toString(),
        );
      } else if (devDeps.contains(c.name)) {
        yamlEditor.update(
          ['dev_dependencies', c.name],
          // TODO: Fix support for third-party pub servers
          c.constraint.toString(),
        );
      }
    }

    /// Windows line endings are already handled by [yamlEditor]
    writeTextFile(entrypoint.pubspecPath, yamlEditor.toString());
  }

  /// Outputs a summary of changes made to `pubspec.yaml`.
  void _outputChangeSummary(
    Map<PackageRange, PackageRange> changes,
  ) {
    ArgumentError.checkNotNull(changes, 'changes');

    if (changes.isEmpty) {
      log.message('No changes to pubspec.yaml!');
    } else {
      final s = changes.length == 1 ? '' : 's';

      log.message('${changes.length} change$s to `pubspec.yaml`:');
      changes.forEach((from, to) {
        log.message('${from.name}: ${from.constraint} -> ${to.constraint}');
      });
    }
  }

  /// Returns new pubspec with the same dependencies as [original], but with:
  ///  * the lower-bound of hosted package constraint set to first null-safety
  ///    compatible version, and,
  ///  * the upper-bound of hosted package constraints removed.
  ///
  /// Only changes listed in [upgradeOnly] will have their constraints touched.
  ///
  /// Throws [ApplicationException] if one of the dependencies does not have
  /// a null-safety compatible version.
  Future<Pubspec> _upgradeToNullSafetyConstraints(
    Pubspec original,
    List<String> upgradeOnly,
  ) async {
    ArgumentError.checkNotNull(original, 'original');
    ArgumentError.checkNotNull(upgradeOnly, 'upgradeOnly');

    final hasNoNullSafetyVersions = <String>{};
    final hasNullSafetyVersions = <String>{};

    Future<Iterable<PackageRange>> _removeUpperConstraints(
      Iterable<PackageRange> dependencies,
    ) async =>
        await Future.wait(dependencies.map((dep) async {
          if (dep.source is! HostedSource) {
            return dep;
          }
          if (!upgradeOnly.contains(dep.name)) {
            return dep;
          }

          final boundSource = dep.source.bind(cache);
          final packages = await boundSource.getVersions(dep.toRef());
          packages.sort((a, b) => a.version.compareTo(b.version));

          for (final package in packages) {
            final pubspec = await boundSource.describe(package);
            if (pubspec.languageVersion.supportsNullSafety) {
              hasNullSafetyVersions.add(dep.name);
              return dep.withConstraint(
                VersionRange(min: package.version, includeMin: true),
              );
            }
          }

          hasNoNullSafetyVersions.add(dep.name);
          return null;
        }));

    final deps = _removeUpperConstraints(original.dependencies.values);
    final devDeps = _removeUpperConstraints(original.devDependencies.values);
    await Future.wait([deps, devDeps]);

    if (hasNoNullSafetyVersions.isNotEmpty) {
      throw ApplicationException('''
null-safety compatible versions does not exist for:
 - ${hasNoNullSafetyVersions.join('\n - ')}

You can choose to upgrade only some dependencies to null-safety using:
  dart pub upgrade --nullsafety ${hasNullSafetyVersions.join(' ')}

Warning: Using null-safety features before upgrading all dependencies is
discouraged. For more details see: ${NullSafetyAnalysis.guideUrl}
''');
    }

    return Pubspec(
      original.name,
      version: original.version,
      sdkConstraints: original.sdkConstraints,
      dependencies: await deps,
      devDependencies: await devDeps,
      dependencyOverrides: original.dependencyOverrides.values,
    );
  }
}
