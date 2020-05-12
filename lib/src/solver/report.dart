// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub_semver/pub_semver.dart';

import '../lock_file.dart';
import '../log.dart' as log;
import '../package.dart';
import '../package_name.dart';
import '../source_registry.dart';
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
  final SourceRegistry _sources;
  final Package _root;
  final LockFile _previousLockFile;
  final SolveResult _result;

  /// The dependencies in [_result], keyed by package name.
  final _dependencies = <String, PackageId>{};

  final _output = StringBuffer();

  SolveReport(this._type, this._sources, this._root, this._previousLockFile,
      this._result) {
    // Fill the map so we can use it later.
    for (var id in _result.packages) {
      _dependencies[id.name] = id;
    }
  }

  /// Displays a report of the results of the version resolution relative to
  /// the previous lock file.
  void show() {
    _reportChanges();
    _reportOverrides();
  }

  /// Displays a one-line message summarizing what changes were made (or would
  /// be made) to the lockfile.
  ///
  /// If [dryRun] is true, describes it in terms of what would be done.
  void summarize({bool dryRun = false}) {
    // Count how many dependencies actually changed.
    var dependencies = _dependencies.keys.toSet();
    dependencies.addAll(_previousLockFile.packages.keys);
    dependencies.remove(_root.name);

    var numChanged = dependencies.where((name) {
      var oldId = _previousLockFile.packages[name];
      var newId = _dependencies[name];

      // Added or removed dependencies count.
      if (oldId == null) return true;
      if (newId == null) return true;

      // The dependency existed before, so see if it was modified.
      return oldId != newId;
    }).length;

    if (dryRun) {
      if (numChanged == 0) {
        log.message('No dependencies would change.');
      } else if (numChanged == 1) {
        log.message('Would change $numChanged dependency.');
      } else {
        log.message('Would change $numChanged dependencies.');
      }
    } else {
      if (numChanged == 0) {
        if (_type == SolveType.GET) {
          log.message('Got dependencies!');
        } else {
          log.message('No dependencies changed.');
        }
      } else if (numChanged == 1) {
        log.message('Changed $numChanged dependency!');
      } else {
        log.message('Changed $numChanged dependencies!');
      }
    }
  }

  /// Displays a report of all of the previous and current dependencies and
  /// how they have changed.
  void _reportChanges() {
    _output.clear();

    // Show the new set of dependencies ordered by name.
    var names = _result.packages.map((id) => id.name).toList();
    names.remove(_root.name);
    names.sort();
    names.forEach(_reportPackage);

    // Show any removed ones.
    var removed = _previousLockFile.packages.keys.toSet();
    removed.removeAll(names);
    removed.remove(_root.name); // Never consider root.
    if (removed.isNotEmpty) {
      _output.writeln('These packages are no longer being depended on:');
      for (var name in ordered(removed)) {
        _reportPackage(name, alwaysShow: true);
      }
    }

    log.message(_output);
  }

  /// Displays a warning about the overrides currently in effect.
  void _reportOverrides() {
    _output.clear();

    if (_root.dependencyOverrides.isNotEmpty) {
      _output.writeln('Warning: You are using these overridden dependencies:');

      for (var name in ordered(_root.dependencyOverrides.keys)) {
        _reportPackage(name, alwaysShow: true, highlightOverride: false);
      }

      log.warning(_output);
    }
  }

  /// Displays a two-line message, number of outdated packages and an
  /// instruction to run `pub outdated` if outdated packages are detected.
  void reportOutdated() {
    final outdatedPackagesCount = _result.packages.where((id) {
      final versions = _result.availableVersions[id.name];
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
          'dependency constraints.\nTry `pub outdated` for more information.');
    }
  }

  /// Reports the results of the upgrade on the package named [name].
  ///
  /// If [alwaysShow] is true, the package is reported even if it didn't change,
  /// regardless of [_type]. If [highlightOverride] is true (or absent), writes
  /// "(override)" next to overridden packages.
  void _reportPackage(String name,
      {bool alwaysShow = false, bool highlightOverride = true}) {
    var newId = _dependencies[name];
    var oldId = _previousLockFile.packages[name];
    var id = newId ?? oldId;

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
    } else if (!oldId.samePackage(newId)) {
      icon = log.cyan('* ');
      changed = true;
    } else if (oldId.version < newId.version) {
      icon = log.green('> ');
      changed = true;
    } else if (oldId.version > newId.version) {
      icon = log.cyan('< ');
      changed = true;
    } else {
      // Unchanged.
      icon = '  ';
    }

    if (_type == SolveType.GET && !(alwaysShow || changed || addedOrRemoved)) {
      return;
    }

    _output.write(icon);
    _output.write(log.bold(id.name));
    _output.write(' ');
    _writeId(id);

    // If the package was upgraded, show what it was upgraded from.
    if (changed) {
      _output.write(' (was ');
      _writeId(oldId);
      _output.write(')');
    }

    // Highlight overridden packages.
    if (isOverridden && highlightOverride) {
      _output.write(" ${log.magenta('(overridden)')}");
    }

    // See if there are any newer versions of the package that we were
    // unable to upgrade to.
    if (newId != null && _type != SolveType.DOWNGRADE) {
      var versions = _result.availableVersions[newId.name];

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

      // If there are newer stable versions, only show those.
      String message;
      if (newerStable) {
        message = '(${maxAll(versions, Version.prioritize)} available)';
      } else if (newerUnstable) {
        message = '(${maxAll(versions)} available)';
      }

      if (message != null) _output.write(' ${log.cyan(message)}');
    }

    _output.writeln();
  }

  /// Writes a terse description of [id] (not including its name) to the output.
  void _writeId(PackageId id) {
    _output.write(id.version);

    if (id.source != _sources.defaultSource) {
      var description = id.source.formatDescription(id.description);
      _output.write(' from ${id.source} $description');
    }
  }
}
