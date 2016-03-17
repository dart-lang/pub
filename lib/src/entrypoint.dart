// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:barback/barback.dart';
import 'package:package_config/packages_file.dart' as packages_file;
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

import 'barback/asset_environment.dart';
import 'io.dart';
import 'lock_file.dart';
import 'log.dart' as log;
import 'package.dart';
import 'package_graph.dart';
import 'sdk.dart' as sdk;
import 'solver/version_solver.dart';
import 'source/cached.dart';
import 'source/unknown.dart';
import 'system_cache.dart';
import 'utils.dart';

/// A RegExp to match the SDK constraint in a lock file.
final _sdkConstraint = new RegExp(r'^sdk: "?([^"]*)"?$', multiLine: true);

/// The context surrounding the root package pub is operating on.
///
/// Pub operates over a directed graph of dependencies that starts at a root
/// "entrypoint" package. This is typically the package where the current
/// working directory is located. An entrypoint knows the [root] package it is
/// associated with and is responsible for managing the "packages" directory
/// for it.
///
/// That directory contains symlinks to all packages used by an app. These links
/// point either to the [SystemCache] or to some other location on the local
/// filesystem.
///
/// While entrypoints are typically applications, a pure library package may end
/// up being used as an entrypoint. Also, a single package may be used as an
/// entrypoint in one context but not in another. For example, a package that
/// contains a reusable library may not be the entrypoint when used by an app,
/// but may be the entrypoint when you're running its tests.
class Entrypoint {
  /// The root package this entrypoint is associated with.
  final Package root;

  /// The system-wide cache which caches packages that need to be fetched over
  /// the network.
  final SystemCache cache;

  /// Whether to create and symlink a "packages" directory containing links to
  /// the installed packages.
  final bool _packageSymlinks;

  /// Whether this entrypoint is in memory only, as opposed to representing a
  /// real directory on disk.
  final bool _inMemory;

  /// Whether this is an entrypoint for a globally-activated package.
  final bool isGlobal;

  /// The lockfile for the entrypoint.
  ///
  /// If not provided to the entrypoint, it will be loaded lazily from disk.
  LockFile get lockFile {
    if (_lockFile != null) return _lockFile;

    if (!fileExists(lockFilePath)) {
      _lockFile = new LockFile.empty(cache.sources);
    } else {
      _lockFile = new LockFile.load(lockFilePath, cache.sources);
    }

    return _lockFile;
  }
  LockFile _lockFile;

  /// The package graph for the application and all of its transitive
  /// dependencies.
  ///
  /// Throws a [DataError] if the `.packages` file isn't up-to-date relative to
  /// the pubspec and the lockfile.
  PackageGraph get packageGraph {
    if (_packageGraph != null) return _packageGraph;

    assertUpToDate();
    var packages = new Map.fromIterable(lockFile.packages.values,
        key: (id) => id.name,
        value: (id) => cache.sources.load(id));
    packages[root.name] = root;

    _packageGraph = new PackageGraph(this, lockFile, packages);
    return _packageGraph;
  }
  PackageGraph _packageGraph;

  /// The path to the entrypoint's "packages" directory.
  String get packagesDir => root.path('packages');

  /// The path to the entrypoint's ".packages" file.
  String get packagesFile => root.path('.packages');

  /// The path to the entrypoint package's pubspec.
  String get pubspecPath => root.path('pubspec.yaml');

  /// The path to the entrypoint package's lockfile.
  String get lockFilePath => root.path('pubspec.lock');

  /// The path to the directory containing precompiled dependencies.
  ///
  /// We just precompile the debug version of a package. We're mostly interested
  /// in improving speed for development iteration loops, which usually use
  /// debug mode.
  String get _precompiledDepsPath => root.path('.pub', 'deps', 'debug');

  /// The path to the directory containing dependency executable snapshots.
  String get _snapshotPath => root.path('.pub', 'bin');

  /// Loads the entrypoint from a package at [rootDir].
  ///
  /// If [packageSymlinks] is `true`, this will create a "packages" directory
  /// with symlinks to the installed packages. This directory will be symlinked
  /// into any directory that might contain an entrypoint.
  Entrypoint(String rootDir, SystemCache cache, {bool packageSymlinks: true,
          this.isGlobal: false})
      : root = new Package.load(null, rootDir, cache.sources),
        cache = cache,
        _packageSymlinks = packageSymlinks,
        _inMemory = false;

  /// Creates an entrypoint given package and lockfile objects.
  Entrypoint.inMemory(this.root, this._lockFile, this.cache,
          {this.isGlobal: false})
      : _packageSymlinks = false,
        _inMemory = true;

  /// Creates an entrypoint given a package and a [solveResult], from which the
  /// package graph and lockfile will be computed.
  Entrypoint.fromSolveResult(this.root, this.cache, SolveResult solveResult,
          {this.isGlobal: false})
      : _packageSymlinks = false,
        _inMemory = true {
    _packageGraph = new PackageGraph.fromSolveResult(this, solveResult);
    _lockFile = _packageGraph.lockFile;
  }

  /// Gets all dependencies of the [root] package.
  ///
  /// Performs version resolution according to [SolveType].
  ///
  /// [useLatest], if provided, defines a list of packages that will be
  /// unlocked and forced to their latest versions. If [upgradeAll] is
  /// true, the previous lockfile is ignored and all packages are re-resolved
  /// from scratch. Otherwise, it will attempt to preserve the versions of all
  /// previously locked packages.
  ///
  /// Shows a report of the changes made relative to the previous lockfile. If
  /// this is an upgrade or downgrade, all transitive dependencies are shown in
  /// the report. Otherwise, only dependencies that were changed are shown. If
  /// [dryRun] is `true`, no physical changes are made.
  ///
  /// If [precompile] is `true` (the default), this snapshots dependencies'
  /// executables and runs transformers on transformed dependencies.
  ///
  /// Updates [lockFile] and [packageRoot] accordingly.
  Future acquireDependencies(SolveType type, {List<String> useLatest,
      bool dryRun: false, bool precompile: true}) async {
    var result = await resolveVersions(type, cache.sources, root,
        lockFile: lockFile, useLatest: useLatest);
    if (!result.succeeded) throw result.error;

    result.showReport(type);

    if (dryRun) {
      result.summarizeChanges(type, dryRun: dryRun);
      return;
    }

    // Install the packages and maybe link them into the entrypoint.
    if (_packageSymlinks) {
      cleanDir(packagesDir);
    } else {
      deleteEntry(packagesDir);
    }

    await Future.wait(result.packages.map(_get));
    _saveLockFile(result);

    if (_packageSymlinks) _linkSelf();
    _linkOrDeleteSecondaryPackageDirs();

    result.summarizeChanges(type, dryRun: dryRun);

    /// Build a package graph from the version solver results so we don't
    /// have to reload and reparse all the pubspecs.
    _packageGraph = new PackageGraph.fromSolveResult(this, result);
    packageGraph.loadTransformerCache().clearIfOutdated(result.changedPackages);

    try {
      if (precompile) {
        await _precompileDependencies(changed: result.changedPackages);
        await precompileExecutables(changed: result.changedPackages);
      } else {
        // If precompilation is disabled, delete any stale cached dependencies
        // or snapshots.
        _deletePrecompiledDependencies(
            _dependenciesToPrecompile(changed: result.changedPackages));
        _deleteExecutableSnapshots(changed: result.changedPackages);
      }
    } catch (error, stackTrace) {
      // Just log exceptions here. Since the method is just about acquiring
      // dependencies, it shouldn't fail unless that fails.
      log.exception(error, stackTrace);
    }

    writeTextFile(packagesFile, lockFile.packagesFile(root.name));
  }

  /// Precompile any transformed dependencies of the entrypoint.
  ///
  /// If [changed] is passed, only dependencies whose contents might be changed
  /// if one of the given packages changes will be recompiled.
  Future _precompileDependencies({Iterable<String> changed}) async {
    if (changed != null) changed = changed.toSet();

    var dependenciesToPrecompile = _dependenciesToPrecompile(changed: changed);
    _deletePrecompiledDependencies(dependenciesToPrecompile);
    if (dependenciesToPrecompile.isEmpty) return;

    try {
      await log.progress("Precompiling dependencies", () async {
        var packagesToLoad =
            unionAll(dependenciesToPrecompile.map(
                packageGraph.transitiveDependencies))
            .map((package) => package.name).toSet();

        var environment = await AssetEnvironment.create(this, BarbackMode.DEBUG,
            packages: packagesToLoad, useDart2JS: false);

        /// Ignore barback errors since they'll be emitted via [getAllAssets]
        /// below.
        environment.barback.errors.listen((_) {});

        // TODO(nweiz): only get assets from [dependenciesToPrecompile] so as
        // not to trigger unnecessary lazy transformers.
        var assets = await environment.barback.getAllAssets();
        await waitAndPrintErrors(assets.map((asset) async {
          if (!dependenciesToPrecompile.contains(asset.id.package)) return;

          var destPath = p.join(
              _precompiledDepsPath, asset.id.package, p.fromUri(asset.id.path));
          ensureDir(p.dirname(destPath));
          await createFileFromStream(asset.read(), destPath);
        }));

        log.message("Precompiled " +
            toSentence(ordered(dependenciesToPrecompile).map(log.bold)) + ".");
      });
    } catch (_) {
      // TODO(nweiz): When barback does a better job of associating errors with
      // assets (issue 19491), catch and handle compilation errors on a
      // per-package basis.
      for (var package in dependenciesToPrecompile) {
        deleteEntry(p.join(_precompiledDepsPath, package));
      }
      rethrow;
    }
  }

  /// Returns the set of dependencies that need to be precompiled.
  ///
  /// If [changed] is passed, only dependencies whose contents might be changed
  /// if one of the given packages changes will be returned.
  Set<String> _dependenciesToPrecompile({Iterable<String> changed}) {
    return packageGraph.packages.values.where((package) {
      if (package.pubspec.transformers.isEmpty) return false;
      if (packageGraph.isPackageMutable(package.name)) return false;
      if (!dirExists(p.join(_precompiledDepsPath, package.name))) return true;
      if (changed == null) return true;

      /// Only recompile [package] if any of its transitive dependencies have
      /// changed. We check all transitive dependencies because it's possible
      /// that a transformer makes decisions based on their contents.
      return overlaps(
          packageGraph.transitiveDependencies(package.name)
              .map((package) => package.name).toSet(),
          changed);
    }).map((package) => package.name).toSet();
  }

  /// Deletes outdated precompiled dependencies.
  ///
  /// This deletes the precompilations of all packages in [packages], as well as
  /// any packages that are now untransformed or mutable.
  void _deletePrecompiledDependencies([Iterable<String> packages]) {
    if (!dirExists(_precompiledDepsPath)) return;

    // Delete any cached dependencies that are going to be recached.
    packages ??= [];
    for (var package in packages) {
      var path = p.join(_precompiledDepsPath, package);
      if (dirExists(path)) deleteEntry(path);
    }

    // Also delete any cached dependencies that should no longer be cached.
    for (var subdir in listDir(_precompiledDepsPath)) {
      var package = packageGraph.packages[p.basename(subdir)];
      if (package == null || package.pubspec.transformers.isEmpty ||
          packageGraph.isPackageMutable(package.name)) {
        deleteEntry(subdir);
      }
    }
  }

  /// Precompiles all executables from dependencies that don't transitively
  /// depend on [this] or on a path dependency.
  Future precompileExecutables({Iterable<String> changed}) async {
    _deleteExecutableSnapshots(changed: changed);

    var executables = new Map.fromIterable(root.immediateDependencies,
        key: (dep) => dep.name,
        value: (dep) => _executablesForPackage(dep.name));

    for (var package in executables.keys.toList()) {
      if (executables[package].isEmpty) executables.remove(package);
    }

    if (executables.isEmpty) return;

    await log.progress("Precompiling executables", () async {
      ensureDir(_snapshotPath);

      // Make sure there's a trailing newline so our version file matches the
      // SDK's.
      writeTextFile(p.join(_snapshotPath, 'sdk-version'), "${sdk.version}\n");

      var packagesToLoad =
          unionAll(executables.keys.map(packageGraph.transitiveDependencies))
          .map((package) => package.name).toSet();
      var executableIds = unionAll(
          executables.values.map((ids) => ids.toSet()));
      var environment = await AssetEnvironment.create(this, BarbackMode.RELEASE,
          packages: packagesToLoad,
          entrypoints: executableIds,
          useDart2JS: false);
      environment.barback.errors.listen((error) {
        log.error(log.red("Build error:\n$error"));
      });

      await waitAndPrintErrors(executables.keys.map((package) async {
        var dir = p.join(_snapshotPath, package);
        cleanDir(dir);
        await environment.precompileExecutables(package, dir,
            executableIds: executables[package]);
      }));
    });
  }

  /// Deletes outdated cached executable snapshots.
  ///
  /// If [changed] is passed, only dependencies whose contents might be changed
  /// if one of the given packages changes will have their executables deleted.
  void _deleteExecutableSnapshots({Iterable<String> changed}) {
    if (!dirExists(_snapshotPath)) return;

    // If we don't know what changed, we can't safely re-use any snapshots.
    if (changed == null) {
      deleteEntry(_snapshotPath);
      return;
    }
    changed = changed.toSet();

    // If the existing executable was compiled with a different SDK, we need to
    // recompile regardless of what changed.
    // TODO(nweiz): Use the VM to check this when issue 20802 is fixed.
    var sdkVersionPath = p.join(_snapshotPath, 'sdk-version');
    if (!fileExists(sdkVersionPath) ||
        readTextFile(sdkVersionPath) != "${sdk.version}\n") {
      deleteEntry(_snapshotPath);
      return;
    }

    // Clean out any outdated snapshots.
    for (var entry in listDir(_snapshotPath)) {
      if (!dirExists(entry)) continue;

      var package = p.basename(entry);
      if (!packageGraph.packages.containsKey(package) ||
          packageGraph.isPackageMutable(package) ||
          packageGraph.transitiveDependencies(package)
              .any((dep) => changed.contains(dep.name))) {
        deleteEntry(entry);
      }
    }
  }

  /// Returns the list of all executable assets for [packageName] that should be
  /// precompiled.
  List<AssetId> _executablesForPackage(String packageName) {
    var package = packageGraph.packages[packageName];
    var binDir = package.path('bin');
    if (!dirExists(binDir)) return [];
    if (packageGraph.isPackageMutable(packageName)) return [];

    var executables = package.executableIds;

    // If any executables don't exist, recompile all executables.
    //
    // Normally, [_deleteExecutableSnapshots] will ensure that all the outdated
    // executable directories will be deleted, any checking for any non-existent
    // executable will save us a few IO operations over checking each one. If
    // some executables do exist and some do not, the directory is corrupted and
    // it's good to start from scratch anyway.
    var executablesExist = executables.every((executable) =>
        fileExists(p.join(_snapshotPath, packageName,
            "${p.url.basename(executable.path)}.snapshot")));
    if (!executablesExist) return executables;

    // Otherwise, we don't need to recompile.
    return [];
  }

  /// Makes sure the package at [id] is locally available.
  ///
  /// This automatically downloads the package to the system-wide cache as well
  /// if it requires network access to retrieve (specifically, if the package's
  /// source is a [CachedSource]).
  Future _get(PackageId id) async {
    if (id.isRoot) return;

    var source = cache.sources[id.source];
    if (!_packageSymlinks) {
      if (source is CachedSource) await source.downloadToSystemCache(id);
      return;
    }

    var packageDir = p.join(packagesDir, id.name);
    if (entryExists(packageDir)) deleteEntry(packageDir);
    await source.get(id, packageDir);
  }

  /// Throws a [DataError] if the `.packages` file doesn't exist or if it's
  /// out-of-date relative to the lockfile or the pubspec.
  void assertUpToDate() {
    if (_inMemory) return;

    if (!entryExists(lockFilePath)) {
      dataError('No pubspec.lock file found, please run "pub get" first.');
    }

    if (!entryExists(packagesFile)) {
      dataError('No .packages file found, please run "pub get" first.');
    }

    // Manually parse the lockfile because a full YAML parse is relatively slow
    // and this is on the hot path for "pub run".
    var lockFileText = readTextFile(lockFilePath);
    var hasPathDependencies = lockFileText.contains("\n    source: path\n");

    var pubspecModified = new File(pubspecPath).lastModifiedSync();
    var lockFileModified = new File(lockFilePath).lastModifiedSync();

    var touchedLockFile = false;
    if (lockFileModified.isBefore(pubspecModified) ||
        hasPathDependencies) {
      if (_isLockFileUpToDate() && _arePackagesAvailable()) {
        touchedLockFile = true;
        touch(lockFilePath);
      } else {
        dataError('The pubspec.yaml file has changed since the pubspec.lock '
            'file was generated, please run "pub get" again.');
      }
    }

    var packagesModified = new File(packagesFile).lastModifiedSync();
    if (packagesModified.isBefore(lockFileModified)) {
      if (_isPackagesFileUpToDate()) {
        touch(packagesFile);
      } else {
        dataError('The pubspec.lock file has changed since the .packages file '
            'was generated, please run "pub get" again.');
      }
    } else if (touchedLockFile) {
      touch(packagesFile);
    }

    var sdkConstraint = _sdkConstraint.firstMatch(lockFileText);
    if (sdkConstraint != null) {
      var parsedConstraint = new VersionConstraint.parse(sdkConstraint[1]);
      if (!parsedConstraint.allows(sdk.version)) {
        dataError("Dart ${sdk.version} is incompatible with your dependencies' "
            "SDK constraints. Please run \"pub get\" again.");
      }
    }
  }

  /// Determines whether or not the lockfile is out of date with respect to the
  /// pubspec.
  ///
  /// This will be `false` if any mutable pubspec contains dependencies that are
  /// not in the lockfile or that don't match what's in there.
  bool _isLockFileUpToDate() {
    if (!root.immediateDependencies.every(_isDependencyUpToDate)) return false;

    var overrides = root.dependencyOverrides.map((dep) => dep.name).toSet();

    // Check that uncached dependencies' pubspecs are also still satisfied,
    // since they're mutable and may have changed since the last get.
    return lockFile.packages.values.every((id) {
      var source = cache.sources[id.name];
      if (source is! CachedSource) return true;

      return cache.sources.load(id).dependencies.every((dep) =>
          overrides.contains(dep.name) || _isDependencyUpToDate(dep));
    });
  }

  /// Returns whether the locked version of [dep] matches the dependency.
  bool _isDependencyUpToDate(PackageDep dep) {
    var locked = lockFile.packages[dep.name];
    if (locked == null) return false;

    if (dep.source != locked.source) return false;

    if (!dep.constraint.allows(locked.version)) return false;

    var source = cache.sources[dep.source];
    if (source == null) return false;

    return source.descriptionsEqual(dep.description, locked.description);
  }

  /// Determines whether all of the packages in the lockfile are already
  /// installed and available.
  bool _arePackagesAvailable() {
    return lockFile.packages.values.every((package) {
      var source = cache.sources[package.source];
      if (source is UnknownSource) return false;

      // We only care about cached sources. Uncached sources aren't "installed".
      // If one of those is missing, we want to show the user the file not
      // found error later since installing won't accomplish anything.
      if (source is! CachedSource) return true;

      // Get the directory.
      var dir = source.getDirectory(package);
      // See if the directory is there and looks like a package.
      return dirExists(dir) && fileExists(p.join(dir, "pubspec.yaml"));
    });
  }

  /// Determines whether or not the `.packages` file is out of date with respect
  /// to the lockfile.
  ///
  /// This will be `false` if the packages file contains dependencies that are
  /// not in the lockfile or that don't match what's in there.
  bool _isPackagesFileUpToDate() {
    var packages = packages_file.parse(
        new File(packagesFile).readAsBytesSync(),
        p.toUri(packagesFile));

    return lockFile.packages.values.every((lockFileId) {
      var source = cache.sources[lockFileId.source];

      // It's very unlikely that the lockfile is invalid here, but it's not
      // impossible—for example, the user may have a very old application
      // package with a checked-in lockfile that's newer than the pubspec, but
      // that contains sdk dependencies.
      if (source == null) return false;

      var packagesFileUri = packages[lockFileId.name];
      if (packagesFileUri == null) return false;

      // Pub only generates "file:" and relative URIs.
      if (packagesFileUri.scheme != 'file' &&
          packagesFileUri.scheme.isNotEmpty) {
        return false;
      }

      // Get the dirname of the .packages path, since it's pointing to lib/.
      var packagesFilePath = p.dirname(
          p.join(root.dir, p.fromUri(packagesFileUri)));
      var lockFilePath = p.join(root.dir, source.getDirectory(lockFileId));

      // For cached sources, make sure the directory exists and looks like a
      // package. This is also done by [_arePackagesAvailable] but that may not
      // be run if the lockfile is newer than the pubspec.
      if (source is CachedSource &&
          !dirExists(packagesFilePath) ||
          !fileExists(p.join(packagesFilePath, "pubspec.yaml"))) {
        return false;
      }

      // Make sure that the packages file agrees with the lock file about the
      // path to the package.
      return p.normalize(packagesFilePath) == p.normalize(lockFilePath);
    });
  }

  /// Saves a list of concrete package versions to the `pubspec.lock` file.
  void _saveLockFile(SolveResult result) {
    _lockFile = result.lockFile;
    var lockFilePath = root.path('pubspec.lock');
    writeTextFile(lockFilePath, _lockFile.serialize(root.dir));
  }

  /// Creates a self-referential symlink in the `packages` directory that allows
  /// a package to import its own files using `package:`.
  void _linkSelf() {
    var linkPath = p.join(packagesDir, root.name);
    // Create the symlink if it doesn't exist.
    if (entryExists(linkPath)) return;
    ensureDir(packagesDir);
    createPackageSymlink(root.name, root.dir, linkPath,
        isSelfLink: true, relative: true);
  }

  /// If [packageSymlinks] is true, add "packages" directories to the whitelist
  /// of directories that may contain Dart entrypoints.
  ///
  /// Otherwise, delete any "packages" directories in the whitelist of
  /// directories that may contain Dart entrypoints.
  void _linkOrDeleteSecondaryPackageDirs() {
    // Only the main "bin" directory gets a "packages" directory, not its
    // subdirectories.
    var binDir = root.path('bin');
    if (dirExists(binDir)) _linkOrDeleteSecondaryPackageDir(binDir);

    // The others get "packages" directories in subdirectories too.
    for (var dir in ['benchmark', 'example', 'test', 'tool', 'web']) {
      _linkOrDeleteSecondaryPackageDirsRecursively(root.path(dir));
    }
 }

  /// If [packageSymlinks] is true, creates a symlink to the "packages"
  /// directory in [dir] and all its subdirectories.
  ///
  /// Otherwise, deletes any "packages" directories in [dir] and all its
  /// subdirectories.
  void _linkOrDeleteSecondaryPackageDirsRecursively(String dir) {
    if (!dirExists(dir)) return;
    _linkOrDeleteSecondaryPackageDir(dir);
    _listDirWithoutPackages(dir)
        .where(dirExists)
        .forEach(_linkOrDeleteSecondaryPackageDir);
  }

  // TODO(nweiz): roll this into [listDir] in io.dart once issue 4775 is fixed.
  /// Recursively lists the contents of [dir], excluding hidden `.DS_Store`
  /// files and `package` files.
  List<String> _listDirWithoutPackages(dir) {
    return flatten(listDir(dir).map((file) {
      if (p.basename(file) == 'packages') return [];
      if (!dirExists(file)) return [];
      var fileAndSubfiles = [file];
      fileAndSubfiles.addAll(_listDirWithoutPackages(file));
      return fileAndSubfiles;
    }));
  }

  /// If [packageSymlinks] is true, creates a symlink to the "packages"
  /// directory in [dir].
  ///
  /// Otherwise, deletes a "packages" directories in [dir] if one exists.
  void _linkOrDeleteSecondaryPackageDir(String dir) {
    var symlink = p.join(dir, 'packages');
    if (entryExists(symlink)) deleteEntry(symlink);
    if (_packageSymlinks) createSymlink(packagesDir, symlink, relative: true);
  }
}
