// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// This implements support for dependency-bot style automated upgrades.
/// It is still work in progress - do not rely on the current output.
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import '../command.dart';
import '../exceptions.dart';
import '../io.dart';
import '../lock_file.dart';
import '../log.dart' as log;
import '../package.dart';
import '../package_name.dart';
import '../pubspec.dart';
import '../pubspec_utils.dart';
import '../solver.dart';
import '../system_cache.dart';
import '../utils.dart';

class DependencyServicesReportCommand extends PubCommand {
  @override
  String get name => 'report';
  @override
  String get description =>
      'Output a machine-digestible report of the upgrade options for each dependency.';
  @override
  String get argumentsDescription => '[options]';

  @override
  bool get takesArguments => false;

  DependencyServicesReportCommand() {
    argParser.addOption('directory',
        abbr: 'C', help: 'Run this in the directory<dir>.', valueHelp: 'dir');
  }

  @override
  Future<void> runProtected() async {
    final compatiblePubspec = stripDependencyOverrides(entrypoint.root.pubspec);

    final breakingPubspec = stripVersionUpperBounds(compatiblePubspec);

    final compatiblePackagesResult =
        await _tryResolve(compatiblePubspec, cache);

    final breakingPackagesResult = await _tryResolve(breakingPubspec, cache);

    // The packages in the current lockfile or resolved from current pubspec.yaml.
    late Map<String, PackageId> currentPackages;

    if (fileExists(entrypoint.lockFilePath)) {
      currentPackages =
          Map<String, PackageId>.from(entrypoint.lockFile.packages);
    } else {
      final resolution = await _tryResolve(entrypoint.root.pubspec, cache) ??
          (throw DataException('Failed to resolve pubspec'));
      currentPackages =
          Map<String, PackageId>.fromIterable(resolution, key: (e) => e.name);
    }
    currentPackages.remove(entrypoint.root.name);

    final dependencies = <Object>[];
    final result = <String, Object>{'dependencies': dependencies};

    Future<List<Object>> _computeUpgradeSet(
      Pubspec rootPubspec,
      PackageId? package, {
      required UpgradeType upgradeType,
    }) async {
      if (package == null) return [];
      final lockFile = entrypoint.lockFile;
      final pubspec = upgradeType == UpgradeType.multiBreaking
          ? stripVersionUpperBounds(rootPubspec)
          : Pubspec(
              rootPubspec.name,
              dependencies: rootPubspec.dependencies.values,
              devDependencies: rootPubspec.devDependencies.values,
              sdkConstraints: rootPubspec.sdkConstraints,
            );

      final dependencySet = dependencySetOfPackage(pubspec, package);
      if (dependencySet != null) {
        // Force the version to be the new version.
        dependencySet[package.name] =
            package.toRef().withConstraint(package.toRange().constraint);
      }

      final resolution = await tryResolveVersions(
        SolveType.get,
        cache,
        Package.inMemory(pubspec),
        lockFile: lockFile,
      );

      // TODO(sigurdm): improve error messages.
      if (resolution == null) {
        throw DataException('Failed resolving');
      }

      return [
        ...resolution.packages.where((r) {
          if (r.name == rootPubspec.name) return false;
          final originalVersion = currentPackages[r.name];
          return originalVersion == null ||
              r.version != originalVersion.version;
        }).map((p) {
          final depset = dependencySetOfPackage(rootPubspec, p);
          final originalConstraint = depset?[p.name]?.constraint;
          return {
            'name': p.name,
            'version': p.version.toString(),
            'kind': _kindString(pubspec, p.name),
            'constraintBumped': originalConstraint == null
                ? null
                : upgradeType == UpgradeType.compatible
                    ? originalConstraint.toString()
                    : VersionConstraint.compatibleWith(p.version).toString(),
            'constraintWidened': originalConstraint == null
                ? null
                : upgradeType == UpgradeType.compatible
                    ? originalConstraint.toString()
                    : _widenConstraint(originalConstraint, p.version)
                        .toString(),
            'constraintBumpedIfNeeded': originalConstraint == null
                ? null
                : upgradeType == UpgradeType.compatible
                    ? originalConstraint.toString()
                    : originalConstraint.allows(p.version)
                        ? originalConstraint.toString()
                        : VersionConstraint.compatibleWith(p.version)
                            .toString(),
            'previousVersion': currentPackages[p.name]?.version.toString(),
            'previousConstraint': originalConstraint?.toString(),
          };
        }),
        for (final oldPackageName in lockFile.packages.keys)
          if (!resolution.packages
              .any((newPackage) => newPackage.name == oldPackageName))
            {
              'name': oldPackageName,
              'version': null,
              'kind':
                  'transitive', // Only transitive constraints can be removed.
              'constraintBumped': null,
              'constraintWidened': null,
              'constraintBumpedIfNeeded': null,
              'previousVersion':
                  currentPackages[oldPackageName]?.version.toString(),
              'previousConstraint': null,
            },
      ];
    }

    for (final package in currentPackages.values) {
      final compatibleVersion = compatiblePackagesResult
          ?.firstWhereOrNull((element) => element.name == package.name);
      final multiBreakingVersion = breakingPackagesResult
          ?.firstWhereOrNull((element) => element.name == package.name);
      final singleBreakingPubspec = Pubspec(
        compatiblePubspec.name,
        version: compatiblePubspec.version,
        sdkConstraints: compatiblePubspec.sdkConstraints,
        dependencies: compatiblePubspec.dependencies.values,
        devDependencies: compatiblePubspec.devDependencies.values,
      );
      final dependencySet =
          dependencySetOfPackage(singleBreakingPubspec, package);
      final kind = _kindString(compatiblePubspec, package.name);
      PackageId? singleBreakingVersion;
      if (dependencySet != null) {
        dependencySet[package.name] = package
            .toRef()
            .withConstraint(stripUpperBound(package.toRange().constraint));
        final singleBreakingPackagesResult =
            await _tryResolve(singleBreakingPubspec, cache);
        singleBreakingVersion = singleBreakingPackagesResult
            ?.firstWhereOrNull((element) => element.name == package.name);
      }
      dependencies.add({
        'name': package.name,
        'version': package.version.toString(),
        'kind': kind,
        'latest':
            (await cache.getLatest(package.toRef(), version: package.version))
                ?.version
                .toString(),
        'constraint':
            _constraintOf(compatiblePubspec, package.name)?.toString(),
        if (compatibleVersion != null)
          'compatible': await _computeUpgradeSet(
              compatiblePubspec, compatibleVersion,
              upgradeType: UpgradeType.compatible),
        'singleBreaking': kind != 'transitive' && singleBreakingVersion == null
            ? []
            : await _computeUpgradeSet(compatiblePubspec, singleBreakingVersion,
                upgradeType: UpgradeType.singleBreaking),
        'multiBreaking': kind != 'transitive' && multiBreakingVersion != null
            ? await _computeUpgradeSet(compatiblePubspec, multiBreakingVersion,
                upgradeType: UpgradeType.multiBreaking)
            : [],
      });
    }
    log.message(JsonEncoder.withIndent('  ').convert(result));
  }
}

VersionConstraint? _constraintOf(Pubspec pubspec, String packageName) {
  return (pubspec.dependencies[packageName] ??
          pubspec.devDependencies[packageName])
      ?.constraint;
}

String _kindString(Pubspec pubspec, String packageName) {
  return pubspec.dependencies.containsKey(packageName)
      ? 'direct'
      : pubspec.devDependencies.containsKey(packageName)
          ? 'dev'
          : 'transitive';
}

/// Try to solve [pubspec] return [PackageId]s in the resolution or `null` if no
/// resolution was found.
Future<List<PackageId>?> _tryResolve(Pubspec pubspec, SystemCache cache) async {
  final solveResult = await tryResolveVersions(
    SolveType.upgrade,
    cache,
    Package.inMemory(pubspec),
  );

  return solveResult?.packages;
}

class DependencyServicesListCommand extends PubCommand {
  @override
  String get name => 'list';

  @override
  String get description =>
      'Output a machine digestible listing of all dependencies';

  @override
  bool get takesArguments => false;

  DependencyServicesListCommand() {
    argParser.addOption('directory',
        abbr: 'C', help: 'Run this in the directory<dir>.', valueHelp: 'dir');
  }

  @override
  Future<void> runProtected() async {
    final pubspec = entrypoint.root.pubspec;

    final currentPackages = fileExists(entrypoint.lockFilePath)
        ? entrypoint.lockFile.packages.values.toList()
        : (await _tryResolve(pubspec, cache) ?? <PackageId>[]);

    final dependencies = <Object>[];
    final result = <String, Object>{'dependencies': dependencies};

    for (final package in currentPackages) {
      dependencies.add({
        'name': package.name,
        'version': package.version.toString(),
        'kind': _kindString(pubspec, package.name),
        'constraint': _constraintOf(pubspec, package.name).toString(),
      });
    }
    log.message(JsonEncoder.withIndent('  ').convert(result));
  }
}

enum UpgradeType {
  /// Only upgrade pubspec.lock.
  compatible,

  /// Unlock at most one dependency in pubspec.yaml.
  singleBreaking,

  /// Unlock any dependencies in pubspec.yaml needed for getting the
  /// latest resolvable version.
  multiBreaking,
}

class DependencyServicesApplyCommand extends PubCommand {
  @override
  String get name => 'apply';

  @override
  String get description =>
      'Updates pubspec.yaml and pubspec.lock according to input.';

  @override
  bool get takesArguments => true;

  DependencyServicesApplyCommand() {
    argParser.addOption('directory',
        abbr: 'C', help: 'Run this in the directory <dir>.', valueHelp: 'dir');
  }

  @override
  Future<void> runProtected() async {
    YamlEditor(readTextFile(entrypoint.pubspecPath));
    final toApply = <_PackageVersion>[];
    final input = json.decode(await utf8.decodeStream(stdin));
    for (final change in input['dependencyChanges']) {
      toApply.add(
        _PackageVersion(
          change['name'],
          change['version'] != null ? Version.parse(change['version']) : null,
          change['constraint'] != null
              ? VersionConstraint.parse(change['constraint'])
              : null,
        ),
      );
    }

    final pubspec = entrypoint.root.pubspec;
    final pubspecEditor = YamlEditor(readTextFile(entrypoint.pubspecPath));
    final lockFile = fileExists(entrypoint.lockFilePath)
        ? readTextFile(entrypoint.lockFilePath)
        : null;
    final lockFileYaml = lockFile == null ? null : loadYaml(lockFile);
    final lockFileEditor = lockFile == null ? null : YamlEditor(lockFile);
    for (final p in toApply) {
      final targetPackage = p.name;
      final targetVersion = p.version;
      final targetConstraint = p.constraint;

      if (targetConstraint != null) {
        final section = pubspec.dependencies[targetPackage] != null
            ? 'dependencies'
            : 'dev_dependencies';
        pubspecEditor
            .update([section, targetPackage], targetConstraint.toString());
      } else if (targetVersion != null) {
        final constraint = _constraintOf(pubspec, targetPackage);
        if (constraint != null && !constraint.allows(targetVersion)) {
          final section = pubspec.dependencies[targetPackage] != null
              ? 'dependencies'
              : 'dev_dependencies';
          pubspecEditor.update([section, targetPackage],
              VersionConstraint.compatibleWith(targetVersion).toString());
        }
      }
      if (targetVersion != null &&
          lockFileEditor != null &&
          lockFileYaml['packages'].containsKey(targetPackage)) {
        lockFileEditor.update(
            ['packages', targetPackage, 'version'], targetVersion.toString());
      }
      if (targetVersion == null &&
          lockFileEditor != null &&
          !lockFileYaml['packages'].containsKey(targetPackage)) {
        dataError(
          'Trying to remove non-existing transitive dependency $targetPackage.',
        );
      }
    }

    final updatedLockfile = lockFileEditor == null
        ? null
        : LockFile.parse(
            lockFileEditor.toString(),
            cache.sources,
            filePath: entrypoint.lockFilePath,
          );
    await log.warningsOnlyUnlessTerminal(
      () async {
        final updatedPubspec = pubspecEditor.toString();
        // Resolve versions, this will update transitive dependencies that were
        // not passed in the input. And also counts as a validation of the input
        // by ensuring the resolution is valid.
        //
        // We don't use `acquireDependencies` as that downloads all the archives
        // to cache.
        // TODO: Handle HTTP exceptions gracefully!
        final solveResult = await resolveVersions(
          SolveType.get,
          cache,
          Package.inMemory(Pubspec.parse(updatedPubspec, cache.sources,
              location: toUri(entrypoint.pubspecPath))),
          lockFile: updatedLockfile,
        );
        if (pubspecEditor.edits.isNotEmpty) {
          writeTextFile(entrypoint.pubspecPath, updatedPubspec);
        }
        // Only if we originally had a lock-file we write the resulting lockfile back.
        if (lockFileEditor != null) {
          entrypoint.saveLockFile(solveResult);
        }
      },
    );
    // Dummy message.
    log.message(json.encode({'dependencies': []}));
  }
}

class _PackageVersion {
  String name;
  Version? version;
  VersionConstraint? constraint;
  _PackageVersion(this.name, this.version, this.constraint);
}

Map<String, PackageRange>? dependencySetOfPackage(
    Pubspec pubspec, PackageId package) {
  return pubspec.dependencies.containsKey(package.name)
      ? pubspec.dependencies
      : pubspec.devDependencies.containsKey(package.name)
          ? pubspec.devDependencies
          : null;
}

VersionConstraint _widenConstraint(
    VersionConstraint original, Version newVersion) {
  if (original.allows(newVersion)) return original;
  if (original is VersionRange) {
    final min = original.min;
    final max = original.max;
    if (max != null && newVersion >= max) {
      return compatibleWithIfPossible(
        VersionRange(
          min: min,
          includeMin: original.includeMin,
          max: newVersion.nextBreaking.firstPreRelease,
        ),
      );
    }
    if (min != null && newVersion <= min) {
      return compatibleWithIfPossible(
        VersionRange(
            min: newVersion,
            includeMin: true,
            max: max,
            includeMax: original.includeMax),
      );
    }
  }

  if (original.isEmpty) return newVersion;
  throw ArgumentError.value(
      original, 'original', 'Must be a Version range or empty');
}

VersionConstraint compatibleWithIfPossible(VersionRange versionRange) {
  final min = versionRange.min;
  if (min != null && min.nextBreaking.firstPreRelease == versionRange.max) {
    return VersionConstraint.compatibleWith(min);
  }
  return versionRange;
}
