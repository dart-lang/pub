// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:async/async.dart';
import 'package:collection/collection.dart';
import 'package:package_config/packages_file.dart' as packages_file;
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

import 'after_install.dart';
import 'dart.dart' as dart;
import 'exceptions.dart';
import 'http.dart' as http;
import 'io.dart';
import 'lock_file.dart';
import 'log.dart' as log;
import 'package.dart';
import 'package_graph.dart';
import 'package_name.dart';
import 'pubspec.dart';
import 'sdk.dart';
import 'solver.dart';
import 'source/cached.dart';
import 'source/unknown.dart';
import 'system_cache.dart';
import 'utils.dart';

/// A RegExp to match SDK constraints in a lockfile.
final _sdkConstraint = () {
  // This matches both the old-style constraint:
  //
  // ```yaml
  // sdk: ">=1.2.3 <2.0.0"
  // ```
  //
  // and the new-style constraint:
  //
  // ```yaml
  // sdks:
  //   dart: ">=1.2.3 <2.0.0"
  // ```
  var sdkNames = sdks.keys.map((name) => "  " + name).join('|');
  return new RegExp(r'^(' + sdkNames + r'|sdk): "?([^"]*)"?$', multiLine: true);
}();

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
      _lockFile = new LockFile.empty();
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
    var packages = new Map<String, Package>.fromIterable(
        lockFile.packages.values,
        key: (id) => id.name,
        value: (id) => cache.load(id));
    packages[root.name] = root;

    _packageGraph = new PackageGraph(this, lockFile, packages);
    return _packageGraph;
  }

  PackageGraph _packageGraph;

  /// The path to the entrypoint's "packages" directory.
  String get packagesPath => root.path('packages');

  /// The path to the entrypoint's ".packages" file.
  String get packagesFile => root.path('.packages');

  /// The path to the entrypoint package's pubspec.
  String get pubspecPath => root.path('pubspec.yaml');

  /// The path to the entrypoint package's lockfile.
  String get lockFilePath => root.path('pubspec.lock');

  /// The path to the entrypoint package's `.dart_tool/pub` cache directory.
  ///
  /// If the old-style `.pub` directory is being used, this returns that
  /// instead.
  String get cachePath {
    var newPath = root.path('.dart_tool/pub');
    var oldPath = root.path('.pub');
    if (!dirExists(newPath) && dirExists(oldPath)) return oldPath;
    return newPath;
  }

  /// The path to the directory containing dependency executable snapshots.
  String get _snapshotPath => p.join(cachePath, 'bin');

  /// Loads the entrypoint from a package at [rootDir].
  Entrypoint(String rootDir, SystemCache cache, {this.isGlobal: false})
      : root =
            new Package.load(null, rootDir, cache.sources, isRootPackage: true),
        cache = cache,
        _inMemory = false;

  /// Creates an entrypoint given package and lockfile objects.
  Entrypoint.inMemory(this.root, this._lockFile, this.cache,
      {this.isGlobal: false})
      : _inMemory = true;

  /// Creates an entrypoint given a package and a [solveResult], from which the
  /// package graph and lockfile will be computed.
  Entrypoint.fromSolveResult(this.root, this.cache, SolveResult solveResult,
      {this.isGlobal: false})
      : _inMemory = true {
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
  /// executables.
  ///
  /// If [packagesDir] is `true`, this will create "packages" directory with
  /// symlinks to the installed packages. This directory will be symlinked into
  /// any directory that might contain an entrypoint.
  ///
  /// Updates [lockFile] and [packageRoot] accordingly.
  Future acquireDependencies(SolveType type,
      {List<String> useLatest,
      bool dryRun: false,
      bool precompile: true,
      bool packagesDir: false}) async {
    var result = await resolveVersions(type, cache, root,
        lockFile: lockFile, useLatest: useLatest);

    // Log once about all overridden packages.
    if (warnAboutPreReleaseSdkOverrides && result.pubspecs != null) {
      var overriddenPackages = (result.pubspecs.values
              .where((pubspec) => pubspec.dartSdkWasOverridden)
              .map((pubspec) => pubspec.name)
              .toList()
                ..sort())
          .join(', ');
      if (overriddenPackages.isNotEmpty) {
        log.message(log.yellow(
            'Overriding the upper bound Dart SDK constraint to <=${sdk.version} '
            'for the following packages:\n\n${overriddenPackages}\n\n'
            'To disable this you can set the PUB_ALLOW_PRERELEASE_SDK system '
            'environment variable to `false`, or you can silence this message '
            'by setting it to `quiet`.'));
      }
    }

    result.showReport(type);

    if (dryRun) {
      result.summarizeChanges(type, dryRun: dryRun);
      return;
    }

    // Install the packages and maybe link them into the entrypoint.
    if (packagesDir) {
      cleanDir(packagesPath);
    } else {
      deleteEntry(packagesPath);
    }

    await Future
        .wait(result.packages.map((id) => _get(id, packagesDir: packagesDir)));
    _saveLockFile(result);

    if (packagesDir) _linkSelf();
    _linkOrDeleteSecondaryPackageDirs(packagesDir: packagesDir);

    result.summarizeChanges(type, dryRun: dryRun);

    /// Build a package graph from the version solver results so we don't
    /// have to reload and reparse all the pubspecs.
    _packageGraph = new PackageGraph.fromSolveResult(this, result);

    writeTextFile(packagesFile, lockFile.packagesFile(cache, root.name));

    try {
      if (precompile) {
        await precompileExecutables(changed: result.changedPackages);
      } else {
        _deleteExecutableSnapshots(changed: result.changedPackages);
      }

      await runAfterInstallScripts(result);
    } catch (error, stackTrace) {
      // Just log exceptions here. Since the method is just about acquiring
      // dependencies, it shouldn't fail unless that fails.
      log.exception(error, stackTrace);
    }
  }

  /// Precompiles all executables from dependencies that don't transitively
  /// depend on [this] or on a path dependency.
  Future precompileExecutables({Iterable<String> changed}) async {
    migrateCache();
    _deleteExecutableSnapshots(changed: changed);

    var executables = mapMap<String, PackageRange, String, List<String>>(
        root.immediateDependencies,
        value: (name, _) => _executablesForPackage(name));

    for (var package in executables.keys.toList()) {
      if (executables[package].isEmpty) executables.remove(package);
    }

    if (executables.isEmpty) return;

    await log.progress("Precompiling executables", () async {
      ensureDir(_snapshotPath);

      // Make sure there's a trailing newline so our version file matches the
      // SDK's.
      writeTextFile(p.join(_snapshotPath, 'sdk-version'), "${sdk.version}\n");

      await _precompileExecutables(executables);
    });
  }

  //// Precompiles [executables] to snapshots from the filesystem.
  Future _precompileExecutables(Map<String, List<String>> executables) {
    return waitAndPrintErrors(executables.keys.map((package) {
      var dir = p.join(_snapshotPath, package);
      cleanDir(dir);
      return waitAndPrintErrors(executables[package].map((path) {
        var url = p.toUri(p.join(packageGraph.packages[package].dir, path));
        return dart.snapshot(url, p.join(dir, p.basename(path) + '.snapshot'),
            packagesFile: p.toUri(packagesFile),
            name: '$package:${p.basenameWithoutExtension(path)}');
      }));
    }));
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
          packageGraph
              .transitiveDependencies(package)
              .any((dep) => changed.contains(dep.name))) {
        deleteEntry(entry);
      }
    }
  }

  /// Returns the list of all paths within [packageName] that should be
  /// precompiled.
  List<String> _executablesForPackage(String packageName) {
    var package = packageGraph.packages[packageName];
    var binDir = package.path('bin');
    if (!dirExists(binDir)) return [];
    if (packageGraph.isPackageMutable(packageName)) return [];

    var executables = package.executablePaths;

    // If any executables don't exist, recompile all executables.
    //
    // Normally, [_deleteExecutableSnapshots] will ensure that all the outdated
    // executable directories will be deleted, any checking for any non-existent
    // executable will save us a few IO operations over checking each one. If
    // some executables do exist and some do not, the directory is corrupted and
    // it's good to start from scratch anyway.
    var executablesExist = executables.every((executable) => fileExists(p.join(
        _snapshotPath, packageName, "${p.basename(executable)}.snapshot")));
    if (!executablesExist) return executables;

    // Otherwise, we don't need to recompile.
    return [];
  }

  /// Makes sure the package at [id] is locally available.
  ///
  /// This automatically downloads the package to the system-wide cache as well
  /// if it requires network access to retrieve (specifically, if the package's
  /// source is a [CachedSource]).
  Future _get(PackageId id, {bool packagesDir: false}) {
    return http.withDependencyType(root.dependencyType(id.name), () async {
      if (id.isRoot) return;

      var source = cache.source(id.source);
      if (!packagesDir) {
        if (source is CachedSource) await source.downloadToSystemCache(id);
        return;
      }

      var packagePath = p.join(packagesPath, id.name);
      if (entryExists(packagePath)) deleteEntry(packagePath);
      await source.get(id, packagePath);
    });
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
    if (lockFileModified.isBefore(pubspecModified) || hasPathDependencies) {
      _assertLockFileUpToDate();
      if (_arePackagesAvailable()) {
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

    for (var match in _sdkConstraint.allMatches(lockFileText)) {
      var identifier = match[1] == 'sdk' ? 'dart' : match[1].trim();
      var sdk = sdks[identifier];

      // Don't complain if there's an SDK constraint for an unavailable SDK. For
      // example, the Flutter SDK being unavailable just means that we aren't
      // running from within the `flutter` executable, and we want users to be
      // able to `pub run` non-Flutter tools even in a Flutter app.
      if (!sdk.isAvailable) continue;

      var parsedConstraint = new VersionConstraint.parse(match[2]);
      if (!parsedConstraint.allows(sdk.version)) {
        dataError("${sdk.name} ${sdk.version} is incompatible with your "
            "dependencies' SDK constraints. Please run \"pub get\" again.");
      }
    }
  }

  /// Determines whether or not the lockfile is out of date with respect to the
  /// pubspec.
  ///
  /// If any mutable pubspec contains dependencies that are not in the lockfile
  /// or that don't match what's in there, this will throw a [DataError]
  /// describing the issue.
  void _assertLockFileUpToDate() {
    if (!root.immediateDependencies.values.every(_isDependencyUpToDate)) {
      dataError('The pubspec.yaml file has changed since the pubspec.lock '
          'file was generated, please run "pub get" again.');
    }

    var overrides = new MapKeySet(root.dependencyOverrides);

    // Check that uncached dependencies' pubspecs are also still satisfied,
    // since they're mutable and may have changed since the last get.
    for (var id in lockFile.packages.values) {
      var source = cache.source(id.source);
      if (source is CachedSource) continue;

      try {
        if (cache.load(id).dependencies.values.every((dep) =>
            overrides.contains(dep.name) || _isDependencyUpToDate(dep))) {
          continue;
        }
      } on FileException {
        // If we can't load the pubpsec, the user needs to re-run "pub get".
      }

      dataError('${p.join(source.getDirectory(id), 'pubspec.yaml')} has '
          'changed since the pubspec.lock file was generated, please run "pub '
          'get" again.');
    }
  }

  /// Returns whether the locked version of [dep] matches the dependency.
  bool _isDependencyUpToDate(PackageRange dep) {
    if (dep.name == root.name) return true;

    var locked = lockFile.packages[dep.name];
    return locked != null && dep.allows(locked);
  }

  /// Determines whether all of the packages in the lockfile are already
  /// installed and available.
  bool _arePackagesAvailable() {
    return lockFile.packages.values.every((package) {
      if (package.source is UnknownSource) return false;

      // We only care about cached sources. Uncached sources aren't "installed".
      // If one of those is missing, we want to show the user the file not
      // found error later since installing won't accomplish anything.
      var source = cache.source(package.source);
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
        new File(packagesFile).readAsBytesSync(), p.toUri(packagesFile));

    return lockFile.packages.values.every((lockFileId) {
      // It's very unlikely that the lockfile is invalid here, but it's not
      // impossible—for example, the user may have a very old application
      // package with a checked-in lockfile that's newer than the pubspec, but
      // that contains SDK dependencies.
      if (lockFileId.source is UnknownSource) return false;

      var packagesFileUri = packages[lockFileId.name];
      if (packagesFileUri == null) return false;

      // Pub only generates "file:" and relative URIs.
      if (packagesFileUri.scheme != 'file' &&
          packagesFileUri.scheme.isNotEmpty) {
        return false;
      }

      var source = cache.source(lockFileId.source);

      // Get the dirname of the .packages path, since it's pointing to lib/.
      var packagesFilePath =
          p.dirname(p.join(root.dir, p.fromUri(packagesFileUri)));
      var lockFilePath = p.join(root.dir, source.getDirectory(lockFileId));

      // For cached sources, make sure the directory exists and looks like a
      // package. This is also done by [_arePackagesAvailable] but that may not
      // be run if the lockfile is newer than the pubspec.
      if (source is CachedSource && !dirExists(packagesFilePath) ||
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
    var linkPath = p.join(packagesPath, root.name);
    // Create the symlink if it doesn't exist.
    if (entryExists(linkPath)) return;
    ensureDir(packagesPath);
    createPackageSymlink(root.name, root.dir, linkPath,
        isSelfLink: true, relative: true);
  }

  /// If [packagesDir] is true, add "packages" directories to the whitelist of
  /// directories that may contain Dart entrypoints.
  ///
  /// Otherwise, delete any "packages" directories in the whitelist of
  /// directories that may contain Dart entrypoints.
  void _linkOrDeleteSecondaryPackageDirs({bool packagesDir: false}) {
    // Only the main "bin" directory gets a "packages" directory, not its
    // subdirectories.
    var binDir = root.path('bin');
    if (dirExists(binDir)) {
      _linkOrDeleteSecondaryPackageDir(binDir, packagesDir: packagesDir);
    }

    // The others get "packages" directories in subdirectories too.
    for (var dir in ['benchmark', 'example', 'test', 'tool', 'web']) {
      _linkOrDeleteSecondaryPackageDirsRecursively(root.path(dir),
          packagesDir: packagesDir);
    }
  }

  /// If [packagesDir] is true, creates a symlink to the "packages" directory in
  /// [dir] and all its subdirectories.
  ///
  /// Otherwise, deletes any "packages" directories in [dir] and all its
  /// subdirectories.
  void _linkOrDeleteSecondaryPackageDirsRecursively(String dir,
      {bool packagesDir: false}) {
    if (!dirExists(dir)) return;
    _linkOrDeleteSecondaryPackageDir(dir, packagesDir: packagesDir);
    for (var subdir in _listDirWithoutPackages(dir)) {
      if (!dirExists(subdir)) continue;
      _linkOrDeleteSecondaryPackageDir(subdir, packagesDir: packagesDir);
    }
  }

  // TODO(nweiz): roll this into [listDir] in io.dart once issue 4775 is fixed.
  /// Recursively lists the contents of [dir], excluding hidden `.DS_Store`
  /// files and `package` files.
  Iterable<String> _listDirWithoutPackages(dir) {
    return listDir(dir).expand<String>((file) {
      if (p.basename(file) == 'packages') return [];
      if (!dirExists(file)) return [];
      var fileAndSubfiles = [file];
      fileAndSubfiles.addAll(_listDirWithoutPackages(file));
      return fileAndSubfiles;
    });
  }

  /// If [packagesDir] is true, creates a symlink to the "packages" directory in
  /// [dir].
  ///
  /// Otherwise, deletes a "packages" directories in [dir] if one exists.
  void _linkOrDeleteSecondaryPackageDir(String dir, {bool packagesDir: false}) {
    var symlink = p.join(dir, 'packages');
    if (entryExists(symlink)) deleteEntry(symlink);
    if (packagesDir) createSymlink(packagesPath, symlink, relative: true);
  }

  /// If the entrypoint uses the old-style `.pub` cache directory, migrates it
  /// to the new-style `.dart_tool/pub` directory.
  void migrateCache() {
    var oldPath = root.path('.pub');
    if (!dirExists(oldPath)) return;

    var newPath = root.path('.dart_tool/pub');

    // If both the old and new directories exist, something weird is going on.
    // Do nothing to avoid making things worse. Pub will prefer the new
    // directory anyway.
    if (dirExists(newPath)) return;

    ensureDir(p.dirname(newPath));
    renameDir(oldPath, newPath);
  }

  /// Execute any outstanding Dart scripts in `after_install`.
  Future runAfterInstallScripts(SolveResult result) async {
    // Count how many scripts we could potentially run.
    var allScripts = <String, List<String>>{};

    for (var package in result.changedPackages) {
      var scripts = result.pubspecs[package].afterInstall;
      if (scripts.isNotEmpty) allScripts[package] = scripts;
    }

    // If no scripts need to be run, don't bother updating the cache.
    if (allScripts.isEmpty) return;

    // Figure out what the last time every script was run.
    // If a script has not changed since the last time it was run,
    // Don't run it.
    var systemScriptCache = await AfterInstallCache.load(cache.rootDir);
    var localScriptCache = await AfterInstallCache.load(cachePath);
    var mergedCache = systemScriptCache.merge(localScriptCache);

    // Run scripts in dependencies.
    for (var package in result.changedPackages) {
      var scripts = allScripts[package];
      if (scripts.isEmpty) continue;

      var pkg = package == root.name
          ? root
          : cache.load(result.packages
              .firstWhere((a) => a.name == package, orElse: () => null));

      for (var script in scripts) {
        var absolutePath = p.normalize(p.absolute(p.join(pkg.dir, script)));

        // Don't run the script against there are new changes.
        if (!await mergedCache.isOutdated(absolutePath)) continue;

        // Never trust any third-party scripts. Show a prompt before running scripts.
        if (true || pkg != root) {
          var message = 'package:$package wants to run the script "$absolutePath".';

          // 
        }

        var scriptFile = new File(absolutePath);

        if (await scriptFile.exists()) {
          // We need to change into the package's directory to run its scripts.
          var currentDir = Directory.current;
          Directory.current = pkg.dir;

          // Spawn an isolate for the script.
          var onError = new ReceivePort();
          var onExit = new ReceivePort();
          var onComplete = new Completer();

          onExit.listen(
              (x) => onComplete.isCompleted ? null : onComplete.complete());
          onError.listen((x) =>
              onComplete.isCompleted ? null : onComplete.completeError(x));

          try {
            Isolate.spawnUri(p.toUri(absolutePath), [], null,
                onExit: onExit.sendPort, onError: onError.sendPort);
            await onComplete.future;
          } catch (e) {
            // TODO: Handle errors in scripts!
            print(e);
          } finally {
            // Switch back!
            Directory.current = currentDir;
            onError.close();
            onExit.close();
          }
        }
      }
    }
  }
}
