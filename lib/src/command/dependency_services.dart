// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Implements support for dependency-bot style automated upgrades.
/// It is still work in progress - do not rely on the current output.
library;

import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import '../command.dart';
import '../entrypoint.dart';
import '../exceptions.dart';
import '../io.dart';
import '../lock_file.dart';
import '../log.dart' as log;
import '../package.dart';
import '../package_name.dart';
import '../pubspec.dart';
import '../pubspec_utils.dart';
import '../solver.dart';
import '../solver/version_solver.dart';
import '../source/git.dart';
import '../source/hosted.dart';
import '../source/root.dart';
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
    argParser.addOption(
      'directory',
      abbr: 'C',
      help: 'Run this in the directory <dir>.',
      valueHelp: 'dir',
    );
  }

  @override
  Future<void> runProtected() async {
    final stdinString = await utf8.decodeStream(stdin);
    final input = json.decode(stdinString.isEmpty ? '{}' : stdinString)
        as Map<String, Object?>;
    final additionalConstraints = _parseDisallowed(input, cache);
    final targetPackageName = input['target'];
    if (targetPackageName is! String?) {
      throw FormatException('"target" should be a String.');
    }

    final compatiblePubspec =
        stripDependencyOverrides(entrypoint.workspaceRoot.pubspec);

    final breakingPubspec = stripVersionBounds(compatiblePubspec);

    final compatiblePackagesResult = await _tryResolve(
      Package(
        compatiblePubspec,
        entrypoint.workspaceRoot.dir,
        entrypoint.workspaceRoot.workspaceChildren,
      ),
      cache,
      additionalConstraints: additionalConstraints,
    );

    final breakingPackagesResult = await _tryResolve(
      Package(
        breakingPubspec,
        entrypoint.workspaceRoot.dir,
        entrypoint.workspaceRoot.workspaceChildren,
      ),
      cache,
      additionalConstraints: additionalConstraints,
    );

    final currentPackages = await _computeCurrentPackages(entrypoint, cache);

    final dependencies = <Object>[];
    final result = <String, Object>{'dependencies': dependencies};

    final targetPackage =
        targetPackageName == null ? null : currentPackages[targetPackageName];

    for (final package in targetPackage == null
        ? currentPackages.values
        : <PackageId>[targetPackage]) {
      final compatibleVersion = compatiblePackagesResult
          ?.firstWhereOrNull((element) => element.name == package.name);
      final multiBreakingVersion = breakingPackagesResult
          ?.firstWhereOrNull((element) => element.name == package.name);
      final singleBreakingPubspec = compatiblePubspec.copyWith();

      final dependencySet =
          _dependencySetOfPackage(singleBreakingPubspec, package);
      final kind = _kindString(compatiblePubspec, package.name);
      PackageId? singleBreakingVersion;
      if (dependencySet != null) {
        dependencySet[package.name] = package
            .toRef()
            .withConstraint(stripUpperBound(package.toRange().constraint));
        final singleBreakingPackagesResult = await _tryResolve(
          Package(
            singleBreakingPubspec,
            entrypoint.workspaceRoot.dir,
            entrypoint.workspaceRoot.workspaceChildren,
          ),
          cache,
        );
        singleBreakingVersion = singleBreakingPackagesResult
            ?.firstWhereOrNull((element) => element.name == package.name);
      }
      PackageId? smallestUpgrade;
      if (additionalConstraints.any(
        (c) => c.range.toRef() == package.toRef() && !c.range.allows(package),
      )) {
        // Current version disallowed by restrictions.
        final atLeastCurrentPubspec = atLeastCurrent(
          compatiblePubspec,
          entrypoint.lockFile.packages.values.toList(),
        );

        final smallestUpgradeResult = await _tryResolve(
          Package(
            atLeastCurrentPubspec,
            entrypoint.workspaceRoot.dir,
            entrypoint.workspaceRoot.workspaceChildren,
          ),
          cache,
          solveType: SolveType.downgrade,
          additionalConstraints: additionalConstraints,
        );

        smallestUpgrade = smallestUpgradeResult
            ?.firstWhereOrNull((element) => element.name == package.name);
      }

      Future<List<Object>> computeUpgradeSet(
        PackageId? package,
        _UpgradeType upgradeType,
      ) async {
        return await _computeUpgradeSet(
          compatiblePubspec,
          package,
          entrypoint,
          cache,
          currentPackages: currentPackages,
          upgradeType: upgradeType,
          additionalConstraints: additionalConstraints,
        );
      }

      dependencies.add({
        'name': package.name,
        'version': package.versionOrHash(),
        'kind': kind,
        'source': _source(package, containingDir: directory),
        'latest':
            (await cache.getLatest(package.toRef(), version: package.version))
                ?.versionOrHash(),
        'constraint':
            _constraintOf(compatiblePubspec, package.name)?.toString(),
        'compatible': await computeUpgradeSet(
          compatibleVersion,
          _UpgradeType.compatible,
        ),
        'singleBreaking': kind != 'transitive' && singleBreakingVersion == null
            ? <Object>[]
            : await computeUpgradeSet(
                singleBreakingVersion,
                _UpgradeType.singleBreaking,
              ),
        'multiBreaking': kind != 'transitive' && multiBreakingVersion != null
            ? await computeUpgradeSet(
                multiBreakingVersion,
                _UpgradeType.multiBreaking,
              )
            : <Object>[],
        if (smallestUpgrade != null)
          'smallestUpdate': await computeUpgradeSet(
            smallestUpgrade,
            _UpgradeType.smallestUpdate,
          ),
      });
    }
    log.message(JsonEncoder.withIndent('  ').convert(result));
  }
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
    argParser.addOption(
      'directory',
      abbr: 'C',
      help: 'Run this in the directory <dir>.',
      valueHelp: 'dir',
    );
  }

  @override
  Future<void> runProtected() async {
    final pubspec = entrypoint.workspaceRoot.pubspec;

    final currentPackages = fileExists(entrypoint.lockFilePath)
        ? entrypoint.lockFile.packages.values.toList()
        : (await _tryResolve(
              Package(
                pubspec,
                entrypoint.workspaceRoot.dir,
                entrypoint.workspaceRoot.workspaceChildren,
              ),
              cache,
            ) ??
            <PackageId>[]);

    final dependencies = <Object>[];
    final result = <String, Object>{'dependencies': dependencies};

    for (final package in currentPackages.where((p) => !p.isRoot)) {
      dependencies.add({
        'name': package.name,
        'version': package.versionOrHash(),
        'kind': _kindString(pubspec, package.name),
        'constraint': _constraintOf(pubspec, package.name).toString(),
        'source': _source(package, containingDir: directory),
      });
    }
    log.message(JsonEncoder.withIndent('  ').convert(result));
  }
}

extension on PackageId {
  String versionOrHash() {
    final description = this.description;
    if (description is ResolvedGitDescription) {
      return description.resolvedRef;
    } else {
      return version.toString();
    }
  }
}

enum _UpgradeType {
  /// Only upgrade pubspec.lock.
  compatible,

  /// Unlock at most one dependency in pubspec.yaml.
  singleBreaking,

  /// Unlock any dependencies in pubspec.yaml needed for getting the
  /// latest resolvable version.
  multiBreaking,

  /// Try to upgrade as little as possible.
  smallestUpdate,
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
    argParser.addOption(
      'directory',
      abbr: 'C',
      help: 'Run this in the directory <dir>.',
      valueHelp: 'dir',
    );
  }

  @override
  Future<void> runProtected() async {
    YamlEditor(readTextFile(entrypoint.workspaceRoot.pubspecPath));
    final toApply = <_PackageVersion>[];
    final input = json.decode(await utf8.decodeStream(stdin));
    for (final change in input['dependencyChanges'] as Iterable) {
      toApply.add(
        _PackageVersion(
          change['name'] as String,
          change['version'] as String?,
          change['constraint'] != null
              ? VersionConstraint.parse(change['constraint'] as String)
              : null,
        ),
      );
    }

    final pubspec = entrypoint.workspaceRoot.pubspec;
    final pubspecEditor =
        YamlEditor(readTextFile(entrypoint.workspaceRoot.pubspecPath));
    final lockFile = fileExists(entrypoint.lockFilePath)
        ? readTextFile(entrypoint.lockFilePath)
        : null;
    final lockFileYaml = lockFile == null ? null : loadYaml(lockFile);
    final lockFileEditor = lockFile == null ? null : YamlEditor(lockFile);
    final hasContentHashes = _lockFileHasContentHashes(lockFileYaml);
    final usesPubDev = _lockFileUsesPubDev(lockFileYaml);
    for (final p in toApply) {
      final targetPackage = p.name;
      final targetVersion = p.version;
      final targetConstraint = p.constraint;
      final targetRevision = p.gitRevision;

      if (targetConstraint != null) {
        final section = pubspec.dependencies[targetPackage] != null
            ? 'dependencies'
            : 'dev_dependencies';
        final packageConfig =
            pubspecEditor.parseAt([section, targetPackage]).value;
        if (packageConfig == null || packageConfig is String) {
          pubspecEditor
              .update([section, targetPackage], targetConstraint.toString());
        } else if (packageConfig is Map) {
          pubspecEditor.update(
            [section, targetPackage, 'version'],
            targetConstraint.toString(),
          );
        } else {
          fail(
            'The dependency $targetPackage does not have a map or string as a description',
          );
        }
      } else if (targetVersion != null) {
        final constraint = _constraintOf(pubspec, targetPackage);
        if (constraint != null && !constraint.allows(targetVersion)) {
          final section = pubspec.dependencies[targetPackage] != null
              ? 'dependencies'
              : 'dev_dependencies';
          pubspecEditor.update(
            [section, targetPackage],
            VersionConstraint.compatibleWith(targetVersion).toString(),
          );
        }
      }
      if (lockFileEditor != null) {
        if (targetVersion != null &&
            (lockFileYaml['packages'] as Map).containsKey(targetPackage)) {
          lockFileEditor.update(
            ['packages', targetPackage, 'version'],
            targetVersion.toString(),
          );
          // Remove the now outdated content-hash - it will be restored below
          // after resolution.
          final packageMap = lockFileEditor
              .parseAt(['packages', targetPackage, 'description']).value as Map;
          final hasSha = packageMap.containsKey('sha256');
          if (hasSha) {
            lockFileEditor.remove(
              ['packages', targetPackage, 'description', 'sha256'],
            );
          }
        } else if (targetRevision != null &&
            (lockFileYaml['packages'] as Map).containsKey(targetPackage)) {
          final ref = entrypoint.lockFile.packages[targetPackage]!.toRef();
          final currentDescription = ref.description as GitDescription;
          final updatedRef = PackageRef(
            targetPackage,
            GitDescription(
              url: currentDescription.url,
              path: currentDescription.path,
              ref: targetRevision,
              containingDir: directory,
            ),
          );
          final versions = await cache.getVersions(updatedRef);
          if (versions.isEmpty) {
            dataError(
              'Found no versions of $targetPackage with git revision `$targetRevision`.',
            );
          }
          // GitSource can only return a single version.
          assert(versions.length == 1);

          lockFileEditor.update(
            ['packages', targetPackage, 'version'],
            versions.single.version.toString(),
          );
          lockFileEditor.update(
            ['packages', targetPackage, 'description', 'resolved-ref'],
            targetRevision,
          );
        } else if (targetVersion == null &&
            targetRevision == null &&
            !(lockFileYaml['packages'] as Map).containsKey(targetPackage)) {
          dataError(
            'Trying to remove non-existing transitive dependency $targetPackage.',
          );
        }
      }
    }

    final updatedLockfile = lockFileEditor == null
        ? null
        : LockFile.parse(
            lockFileEditor.toString(),
            cache.sources,
            filePath: entrypoint.lockFilePath,
          );
    await log.errorsOnlyUnlessTerminal(
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
          Package(
            Pubspec.parse(
              updatedPubspec,
              cache.sources,
              location: toUri(entrypoint.workspaceRoot.pubspecPath),
              containingDescription:
                  RootDescription(entrypoint.workspaceRoot.dir),
            ),
            entrypoint.workspaceRoot.dir,
            entrypoint.workspaceRoot.workspaceChildren,
          ),
          lockFile: updatedLockfile,
        );
        if (pubspecEditor.edits.isNotEmpty) {
          writeTextFile(entrypoint.workspaceRoot.pubspecPath, updatedPubspec);
        }
        // Only if we originally had a lock-file we write the resulting lockfile back.
        if (updatedLockfile != null) {
          final updatedPackages = <PackageId>[];
          for (var package in solveResult.packages) {
            if (package.isRoot) continue;
            final description = package.description;
            // Handle content-hashes of hosted dependencies.
            if (description is ResolvedHostedDescription) {
              // Ensure we get content-hashes if the original lock-file had
              // them.
              if (hasContentHashes) {
                if (description.sha256 == null) {
                  // We removed the hash above before resolution - as we get the
                  // locked id back we need to find the content-hash from the
                  // version listing.
                  //
                  // `pub get` gets this version-listing from the downloaded
                  // archive but we don't want to download all archives - so we
                  // copy it from the version listing.
                  package = (await cache.getVersions(package.toRef()))
                      .firstWhere((id) => id == package, orElse: () => package);
                  if ((package.description as ResolvedHostedDescription)
                          .sha256 ==
                      null) {
                    // This happens when we resolved a package from a legacy
                    // server not providing archive_sha256. As a side-effect of
                    // downloading the package we compute and store the sha256.
                    package = (await cache.downloadPackage(package)).packageId;
                  }
                }
              } else {
                // The original pubspec.lock did not have content-hashes. Remove
                // any content hash, so we don't start adding them.
                package = PackageId(
                  package.name,
                  package.version,
                  description.withSha256(null),
                );
              }
              // Keep using https://pub.dartlang.org if the original lockfile
              // used it. This is to support lockfiles from old sdks.
              if (!usesPubDev &&
                  HostedSource.isPubDevUrl(description.description.url)) {
                package = PackageId(
                  package.name,
                  package.version,
                  ResolvedHostedDescription(
                    HostedDescription.raw(
                      package.name,
                      HostedSource.pubDartlangUrl,
                    ),
                    sha256: (package.description as ResolvedHostedDescription)
                        .sha256,
                  ),
                );
              }
            }
            updatedPackages.add(package);
          }

          final newLockFile = LockFile(
            updatedPackages,
            sdkConstraints: updatedLockfile.sdkConstraints,
            mainDependencies: pubspec.dependencies.keys.toSet(),
            devDependencies: pubspec.devDependencies.keys.toSet(),
            overriddenDependencies: pubspec.dependencyOverrides.keys.toSet(),
          );

          newLockFile.writeToFile(entrypoint.lockFilePath, cache);
        }
      },
    );
    // Dummy message.
    log.message(json.encode({'dependencies': <Object>[]}));
  }
}

class _PackageVersion {
  String name;
  Version? version;
  String? gitRevision;
  VersionConstraint? constraint;
  _PackageVersion(this.name, String? versionOrHash, this.constraint)
      : version =
            versionOrHash == null ? null : _tryParseVersion(versionOrHash),
        gitRevision =
            versionOrHash == null ? null : _tryParseHash(versionOrHash);
}

Version? _tryParseVersion(String v) {
  try {
    return Version.parse(v);
  } on FormatException {
    return null;
  }
}

String? _tryParseHash(String v) {
  if (RegExp(r'^[a-fA-F0-9]+$').hasMatch(v)) {
    return v;
  }
  return null;
}

Map<String, PackageRange>? _dependencySetOfPackage(
  Pubspec pubspec,
  PackageId package,
) {
  return pubspec.dependencies.containsKey(package.name)
      ? pubspec.dependencies
      : pubspec.devDependencies.containsKey(package.name)
          ? pubspec.devDependencies
          : null;
}

/// Return a constraint compatible with [newVersion].
///
/// By convention if the original constraint is pinned we return [newVersion]. Otherwise use [VersionConstraint.compatibleWith].
VersionConstraint _bumpConstraint(
  VersionConstraint original,
  Version newVersion,
) {
  if (original.isEmpty) return newVersion;
  if (original is VersionRange) {
    if (original.min == original.max) return newVersion;

    return VersionConstraint.compatibleWith(newVersion);
  }

  throw ArgumentError.value(
    original,
    'original',
    'Must be a Version range or empty',
  );
}

/// Return a constraint compatible with [newVersion], but including [original] as well.
///
/// By convention if the original constraint is pinned, we don't widen the constraint but return [newVersion] instead.
VersionConstraint _widenConstraint(
  VersionConstraint original,
  Version newVersion,
) {
  if (original.allows(newVersion)) return original;
  if (original is VersionRange) {
    final min = original.min;
    final max = original.max;
    if (min == max) return newVersion;
    if (max != null && newVersion >= max) {
      return _compatibleWithIfPossible(
        VersionRange(
          min: min,
          includeMin: original.includeMin,
          max: newVersion.nextBreaking.firstPreRelease,
        ),
      );
    }
    if (min != null && newVersion <= min) {
      return _compatibleWithIfPossible(
        VersionRange(
          min: newVersion,
          includeMin: true,
          max: max,
          includeMax: original.includeMax,
        ),
      );
    }
  }

  if (original.isEmpty) return newVersion;
  throw ArgumentError.value(
    original,
    'original',
    'Must be a Version range or empty',
  );
}

VersionConstraint _compatibleWithIfPossible(VersionRange versionRange) {
  final min = versionRange.min;
  if (min != null && min.nextBreaking.firstPreRelease == versionRange.max) {
    return VersionConstraint.compatibleWith(min);
  }
  return versionRange;
}

/// `true` iff any of the packages described by the [lockfile] has a
/// content-hash.
///
/// Undefined for invalid lock files, but mostly `true`.
bool _lockFileHasContentHashes(dynamic lockfile) {
  if (lockfile is! Map) return true;
  final packages = lockfile['packages'];
  if (packages is! Map) return true;

  /// We consider an empty lockfile ready to get content-hashes.
  if (packages.isEmpty) return true;
  for (final package in packages.values) {
    if (package is! Map) return true;
    final descriptor = package['description'];
    if (descriptor is! Map) return true;
    if (descriptor['sha256'] != null) return true;
  }
  return false;
}

/// Try to solve [package] return [PackageId]s in the resolution or `null` if no
/// resolution was found.
Future<List<PackageId>?> _tryResolve(
  Package package,
  SystemCache cache, {
  SolveType solveType = SolveType.upgrade,
  Iterable<ConstraintAndCause>? additionalConstraints,
}) async {
  final solveResult = await tryResolveVersions(
    solveType,
    cache,
    package,
    additionalConstraints: additionalConstraints,
  );

  return solveResult?.packages;
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

Map<String, Object?> _source(PackageId id, {required String containingDir}) {
  return {
    'type': id.source.name,
    'description':
        id.description.serializeForLockfile(containingDir: containingDir),
  };
}

/// The packages in the current lockfile or resolved from current pubspec.yaml.
/// Does not include the root package.
Future<Map<String, PackageId>> _computeCurrentPackages(
  Entrypoint entrypoint,
  SystemCache cache,
) async {
  late Map<String, PackageId> currentPackages;

  if (fileExists(entrypoint.lockFilePath)) {
    currentPackages = Map<String, PackageId>.from(entrypoint.lockFile.packages);
  } else {
    final resolution = await _tryResolve(entrypoint.workspaceRoot, cache) ??
        (throw DataException('Failed to resolve pubspec'));
    currentPackages = Map<String, PackageId>.fromIterable(
      resolution,
      key: (e) => (e as PackageId).name,
    );
  }
  currentPackages.remove(entrypoint.workspaceRoot.name);
  return currentPackages;
}

Future<List<Object>> _computeUpgradeSet(
  Pubspec rootPubspec,
  PackageId? package,
  Entrypoint entrypoint,
  SystemCache cache, {
  required Map<String, PackageId> currentPackages,
  required _UpgradeType upgradeType,
  required List<ConstraintAndCause> additionalConstraints,
}) async {
  if (package == null) return [];
  final lockFile = entrypoint.lockFile;
  final pubspec = (upgradeType == _UpgradeType.multiBreaking ||
          upgradeType == _UpgradeType.smallestUpdate)
      ? stripVersionBounds(rootPubspec)
      : rootPubspec.copyWith();

  final dependencySet = _dependencySetOfPackage(pubspec, package);
  if (dependencySet != null) {
    // Force the version to be the new version.
    dependencySet[package.name] =
        package.toRef().withConstraint(package.toRange().constraint);
  }

  final resolution = await tryResolveVersions(
    upgradeType == _UpgradeType.smallestUpdate
        ? SolveType.downgrade
        : SolveType.get,
    cache,
    Package(
      pubspec,
      entrypoint.workspaceRoot.dir,
      entrypoint.workspaceRoot.workspaceChildren,
    ),
    lockFile: lockFile,
    additionalConstraints: additionalConstraints,
  );

  // TODO(sigurdm): improve error messages.
  if (resolution == null) {
    return [];
  }

  return [
    ...resolution.packages.where((r) {
      if (r.name == rootPubspec.name) return false;
      final originalVersion = currentPackages[r.name];
      return originalVersion == null || r != originalVersion;
    }).map((p) {
      final depset = _dependencySetOfPackage(rootPubspec, p);
      final originalConstraint = depset?[p.name]?.constraint;
      final currentPackage = currentPackages[p.name];
      return {
        'name': p.name,
        'version': p.versionOrHash(),
        'kind': _kindString(pubspec, p.name),
        'source': _source(p, containingDir: entrypoint.workspaceRoot.dir),
        'constraintBumped': originalConstraint == null
            ? null
            : upgradeType == _UpgradeType.compatible
                ? originalConstraint.toString()
                : _bumpConstraint(originalConstraint, p.version).toString(),
        'constraintWidened': originalConstraint == null
            ? null
            : upgradeType == _UpgradeType.compatible
                ? originalConstraint.toString()
                : _widenConstraint(originalConstraint, p.version).toString(),
        'constraintBumpedIfNeeded': originalConstraint == null
            ? null
            : upgradeType == _UpgradeType.compatible
                ? originalConstraint.toString()
                : originalConstraint.allows(p.version)
                    ? originalConstraint.toString()
                    : _bumpConstraint(originalConstraint, p.version).toString(),
        'previousVersion': currentPackage?.versionOrHash(),
        'previousConstraint': originalConstraint?.toString(),
        'previousSource': currentPackage == null
            ? null
            : _source(
                currentPackage,
                containingDir: entrypoint.workspaceRoot.dir,
              ),
      };
    }),
    // Find packages that were removed by the resolution
    for (final oldPackageName in lockFile.packages.keys)
      if (!resolution.packages
          .any((newPackage) => newPackage.name == oldPackageName))
        {
          'name': oldPackageName,
          'version': null,
          'kind': 'transitive', // Only transitive constraints can be removed.
          'constraintBumped': null,
          'constraintWidened': null,
          'constraintBumpedIfNeeded': null,
          'previousVersion': currentPackages[oldPackageName]?.versionOrHash(),
          'previousConstraint': null,
          'previous': _source(
            currentPackages[oldPackageName]!,
            containingDir: entrypoint.workspaceRoot.dir,
          ),
        },
  ];
}

List<ConstraintAndCause> _parseDisallowed(
  Map<String, Object?> input,
  SystemCache cache,
) {
  final disallowedList = input['disallowed'];
  if (disallowedList == null) {
    return [];
  }
  if (disallowedList is! List<Object?>) {
    throw FormatException('Disallowed should be a list of maps');
  }
  final result = <ConstraintAndCause>[];
  for (final disallowed in disallowedList) {
    if (disallowed is! Map) {
      throw FormatException('Disallowed should be a list of maps');
    }
    final name = disallowed['name'];
    if (name is! String) {
      throw FormatException('"name" should be a string.');
    }
    final url = disallowed['url'] ?? cache.hosted.defaultUrl;
    if (url is! String) {
      throw FormatException('"url" should be a string.');
    }
    final ref = PackageRef(
      name,
      HostedDescription(
        name,
        url,
      ),
    );
    final constraints = disallowed['versions'];
    if (constraints is! List) {
      throw FormatException('"versions" should be a list.');
    }
    final reason = disallowed['reason'];
    if (reason is! String?) {
      throw FormatException('"reason", if present, should be a string.');
    }
    for (final entry in constraints) {
      if (entry is! Map) {
        throw FormatException(
          'Each element of "versions" should be an object.',
        );
      }
      final rangeString = entry['range'];
      if (rangeString is! String) {
        throw FormatException('"range" should be a string');
      }
      final range = VersionConstraint.parse(rangeString);
      result.add(
        ConstraintAndCause(
          PackageRange(ref, VersionConstraint.any.difference(range)),
          reason,
        ),
      );
    }
  }
  return result;
}

/// `true` iff any of the packages described by the [lockfile] uses
/// `https://pub.dev` as url.
///
/// Undefined for invalid lock files, but mostly `true`.
bool _lockFileUsesPubDev(dynamic lockfile) {
  if (lockfile is! Map) return true;
  final packages = lockfile['packages'];
  if (packages is! Map) return true;

  /// We consider an empty lockfile ready to get content-hashes.
  if (packages.isEmpty) return true;
  for (final package in packages.values) {
    if (package is! Map) return true;
    if (package['source'] != 'hosted') continue;
    final descriptor = package['description'];
    if (descriptor is! Map) return true;
    final url = descriptor['url'];
    if (url is! String) return true;
    if (HostedSource.isPubDevUrl(url) && url != HostedSource.pubDartlangUrl) {
      return true;
    }
  }
  return false;
}
