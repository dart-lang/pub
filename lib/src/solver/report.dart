// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as path;
import 'package:pub_semver/pub_semver.dart';

import '../command_runner.dart';
import '../lock_file.dart';
import '../log.dart' as log;
import '../package.dart';
import '../package_name.dart';
import '../source/hosted.dart';
import '../source/root.dart';
import '../system_cache.dart';
import '../utils.dart';
import 'result.dart';
import 'type.dart';

/// Unlike [SolveResult], which is the static data describing a resolution,
/// this class contains the mutable state used while generating the report
/// itself.
///
/// It's a report builder.
class SolveReport {
  final SolveType _type;
  final Package _root;
  final LockFile _previousLockFile;
  final LockFile _newLockFile;
  final SystemCache _cache;
  final bool _dryRun;

  /// The available versions of all selected packages from their source.
  ///
  /// An entry here may not include the full list of versions available if the
  /// given package was locked and did not need to be unlocked during the solve.
  ///
  /// Version list will not contain any retracted package versions.
  final Map<String, List<Version>> _availableVersions;

  final _output = StringBuffer();

  SolveReport(
    this._type,
    this._root,
    this._previousLockFile,
    this._newLockFile,
    this._availableVersions,
    this._cache, {
    required bool dryRun,
  }) : _dryRun = dryRun;

  /// Displays a report of the results of the version resolution in
  /// [_newLockFile] relative to the [_previousLockFile] file.
  Future<void> show() async {
    await _reportChanges();
    await _reportOverrides();
    _checkContentHashesMatchOldLockfile();
  }

_checkContentHashesMatchOldLockfile() {
    final issues = <String>[];

    final newPackageNames = _newLockFile.packages.keys.toSet();
    final oldPackageNames = _previousLockFile.packages.keys.toSet();
    // We only care about packages that exist in both new and old lockfile.
    for (final name in newPackageNames.intersection(oldPackageNames)) {
      final newId = _newLockFile.packages[name]!;
      final oldId = _previousLockFile.packages[name]!;

      // We only care about hosted packages
      final newDescription = newId.description;
      final oldDescription = oldId.description;
      if (newDescription is! ResolvedHostedDescription ||
          oldDescription is! ResolvedHostedDescription) {
        continue;
      }

      // We don't care about changes in the hash if the version number changed!
      if (newId.version != oldId.version) {
        continue;
      }

      // Use the cached content-hashes after downloading to ensure that
      // content-hashes from legacy servers gets used.
      final cachedHash = newDescription.sha256;
      assert(cachedHash != null);

      // Ignore cases where the old lockfile doesn't have a content-hash
      final oldHash = oldDescription.sha256;
      if (oldHash == null) {
        continue;
      }

      if (!fixedTimeBytesEquals(cachedHash, oldHash)) {
        issues.add(
          '$name-${newId.version} from "${newDescription.description.url}"',
        );
      }
    }

    if (issues.isNotEmpty) {
      log.warning('''
The existing content-hash from pubspec.lock doesn't match contents for:
 * ${issues.join('\n * ')}

This indicates one of:
 * The content has changed on the server since you created the pubspec.lock.
 * The pubspec.lock has been corrupted.
${_dryRun ? '' : '\nThe content-hashes in pubspec.lock has been updated.'}

For more information see:
$contentHashesDocumentationUrl
''');
    }
  }

  /// Displays a one-line message summarizing what changes were made (or would
  /// be made) to the lockfile.
  ///
  /// If [dryRun] is true, describes it in terms of what would be done.
  ///
  /// [type] is the type of version resolution that was run.

  /// If [type] is `SolveType.UPGRADE` it also shows the number of packages that
  /// are not at the latest available version and the number of outdated
  /// packages.
  Future<void> summarize() async {
    // Count how many dependencies actually changed.
    var dependencies = _newLockFile.packages.keys.toSet();
    dependencies.addAll(_previousLockFile.packages.keys);
    dependencies.remove(_root.name);

    var numChanged = dependencies.where((name) {
      var oldId = _previousLockFile.packages[name];
      var newId = _newLockFile.packages[name];

      // Added or removed dependencies count.
      if (oldId == null) return true;
      if (newId == null) return true;

      // The dependency existed before, so see if it was modified.
      return oldId != newId;
    }).length;

    var suffix = '';
    if (!_root.isInMemory) {
      final dir = path.normalize(_root.dir);
      if (dir != '.') {
        suffix = ' in $dir';
      }
    }

    if (_dryRun) {
      if (numChanged == 0) {
        log.message('No dependencies would change$suffix.');
      } else if (numChanged == 1) {
        log.message('Would change $numChanged dependency$suffix.');
      } else {
        log.message('Would change $numChanged dependencies$suffix.');
      }
    } else {
      if (numChanged == 0) {
        if (_type == SolveType.get) {
          log.message('Got dependencies$suffix!');
        } else {
          log.message('No dependencies changed$suffix.');
        }
      } else if (numChanged == 1) {
        log.message('Changed $numChanged dependency$suffix!');
      } else {
        log.message('Changed $numChanged dependencies$suffix!');
      }
    }
    if (_type == SolveType.upgrade) {
      await reportDiscontinued();
      reportOutdated();
    }
  }

  /// Displays a report of all of the previous and current dependencies and
  /// how they have changed.
  Future<void> _reportChanges() async {
    _output.clear();

    // Show the new set of dependencies ordered by name.
    var names = _newLockFile.packages.keys.toList();
    names.remove(_root.name);
    names.sort();
    for (final name in names) {
      await _reportPackage(name);
    }
    // Show any removed ones.
    var removed = _previousLockFile.packages.keys.toSet();
    removed.removeAll(names);
    removed.remove(_root.name); // Never consider root.
    if (removed.isNotEmpty) {
      _output.writeln('These packages are no longer being depended on:');
      for (var name in ordered(removed)) {
        await _reportPackage(name, alwaysShow: true);
      }
    }

    log.message(_output);
  }

  /// Displays a warning about the overrides currently in effect.
  Future<void> _reportOverrides() async {
    _output.clear();

    if (_root.dependencyOverrides.isNotEmpty) {
      _output.writeln('Warning: You are using these overridden dependencies:');

      for (var name in ordered(_root.dependencyOverrides.keys)) {
        await _reportPackage(name, alwaysShow: true, highlightOverride: false);
      }

      log.warning(_output);
    }
  }

  /// Displays a single-line message, number of discontinued packages
  /// if discontinued packages are detected.
  Future<void> reportDiscontinued() async {
    var numDiscontinued = 0;
    for (var id in _newLockFile.packages.values) {
      if (id.description is RootDescription) continue;
      final status = await id.source
          .status(id.toRef(), id.version, _cache, maxAge: Duration(days: 3));
      if (status.isDiscontinued &&
          (_root.dependencyType(id.name) == DependencyType.direct ||
              _root.dependencyType(id.name) == DependencyType.dev)) {
        numDiscontinued++;
      }
    }
    if (numDiscontinued > 0) {
      if (numDiscontinued == 1) {
        log.message('1 package is discontinued.');
      } else {
        log.message('$numDiscontinued packages are discontinued.');
      }
    }
  }

  /// Displays a two-line message, number of outdated packages and an
  /// instruction to run `pub outdated` if outdated packages are detected.
  void reportOutdated() {
    final outdatedPackagesCount = _newLockFile.packages.values.where((id) {
      final versions = _availableVersions[id.name]!;
      // A version is counted:
      // - if there is a newer version which is not a pre-release and current
      // version is also not a pre-release or,
      // - if the current version is pre-release then any upgraded version is
      // considered.
      return versions.any((v) =>
          v > id.version && (id.version.isPreRelease || !v.isPreRelease));
    }).length;

    if (outdatedPackagesCount > 0) {
      String packageCountString;
      if (outdatedPackagesCount == 1) {
        packageCountString = '1 package has';
      } else {
        packageCountString = '$outdatedPackagesCount packages have';
      }
      log.message('$packageCountString newer versions incompatible with '
          'dependency constraints.\nTry `$topLevelProgram pub outdated` for more information.');
    }
  }

  /// Reports the results of the upgrade on the package named [name].
  ///
  /// If [alwaysShow] is true, the package is reported even if it didn't change,
  /// regardless of [_type]. If [highlightOverride] is true (or absent), writes
  /// "(override)" next to overridden packages.
  Future<void> _reportPackage(String name,
      {bool alwaysShow = false, bool highlightOverride = true}) async {
    var newId = _newLockFile.packages[name];
    var oldId = _previousLockFile.packages[name];
    var id = newId ?? oldId!;

    var isOverridden = _root.dependencyOverrides.containsKey(id.name);

    // If the package was previously a dependency but the dependency has
    // changed in some way.
    var changed = false;

    // If the dependency was added or removed.
    var addedOrRemoved = false;

    // Show a one-character "icon" describing the change. They are:
    //
    //     ! The package is being overridden.
    //     - The package was removed.
    //     + The package was added.
    //     > The package was upgraded from a lower version.
    //     < The package was downgraded from a higher version.
    //     ~ Package contents has changed, but not the version number.
    //     * Any other change between the old and new package.
    String icon;
    if (isOverridden) {
      icon = log.magenta('! ');
    } else if (newId == null) {
      icon = log.red('- ');
      addedOrRemoved = true;
    } else if (oldId == null) {
      icon = log.green('+ ');
      addedOrRemoved = true;
    } else if (oldId.description.description != newId.description.description) {
      // Eg. a changed source in pubspec.yaml.
      icon = log.cyan('* ');
      changed = true;
    } else if (oldId.version < newId.version) {
      icon = log.green('> ');
      changed = true;
    } else if (oldId.version > newId.version) {
      icon = log.cyan('< ');
      changed = true;
    } else if (oldId.description != newId.description) {
      // Eg. a changed hash or revision.
      icon = log.cyan('~ ');
      changed = true;
    } else {
      // Unchanged.
      icon = '  ';
    }
    String? message;
    // See if there are any newer versions of the package that we were
    // unable to upgrade to.
    if (newId != null && _type != SolveType.downgrade) {
      var versions = _availableVersions[newId.name]!;

      var newerStable = false;
      var newerUnstable = false;

      for (var version in versions) {
        if (version > newId.version) {
          if (version.isPreRelease) {
            newerUnstable = true;
          } else {
            newerStable = true;
          }
        }
      }
      final status = await id.source.status(
        id.toRef(),
        id.version,
        _cache,
        maxAge: Duration(days: 3),
      );

      if (status.isRetracted) {
        if (newerStable) {
          message =
              '(retracted, ${maxAll(versions, Version.prioritize)} available)';
        } else if (newId.version.isPreRelease && newerUnstable) {
          message = '(retracted, ${maxAll(versions)} available)';
        } else {
          message = '(retracted)';
        }
      } else if (status.isDiscontinued &&
          (_root.dependencyType(name) == DependencyType.direct ||
              _root.dependencyType(name) == DependencyType.dev)) {
        if (status.discontinuedReplacedBy == null) {
          message = '(discontinued)';
        } else {
          message =
              '(discontinued replaced by ${status.discontinuedReplacedBy})';
        }
      } else if (newerStable) {
        // If there are newer stable versions, only show those.
        message = '(${maxAll(versions, Version.prioritize)} available)';
      } else if (
          // Only show newer prereleases for versions where a prerelease is
          // already chosen.
          newId.version.isPreRelease && newerUnstable) {
        message = '(${maxAll(versions)} available)';
      }
    }

    if (_type == SolveType.get &&
        !(alwaysShow || changed || addedOrRemoved || message != null)) {
      return;
    }

    _output.write(icon);
    _output.write(log.bold(id.name));
    _output.write(' ');
    _writeId(id);

    // If the package was upgraded, show what it was upgraded from.
    if (changed) {
      _output.write(' (was ');
      _writeId(oldId!);
      _output.write(')');
    }

    // Highlight overridden packages.
    if (isOverridden && highlightOverride) {
      _output.write(" ${log.magenta('(overridden)')}");
    }

    if (message != null) _output.write(' ${log.cyan(message)}');

    _output.writeln();
  }

  /// Writes a terse description of [id] (not including its name) to the output.
  void _writeId(PackageId id) {
    _output.write(id.version);

    if (id.source != _cache.defaultSource) {
      var description = id.description.format();
      _output.write(' from ${id.source} $description');
    }
  }
}
