// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
// ignore: deprecated_member_use
import 'package:package_config/packages_file.dart' as packages_file;
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

import 'dart.dart' as dart;
import 'exceptions.dart';
import 'http.dart' as http;
import 'io.dart';
import 'lock_file.dart';
import 'log.dart' as log;
import 'package.dart';
import 'package_config.dart';
import 'package_config.dart' show PackageConfig;
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
  var sdkNames = sdks.keys.map((name) => '  ' + name).join('|');
  return RegExp(r'^(' + sdkNames + r'|sdk): "?([^"]*)"?$', multiLine: true);
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

  /// Whether this entrypoint exists within the package cache.
  bool get isCached => root.dir != null && p.isWithin(cache.rootDir, root.dir);

  /// Whether this is an entrypoint for a globally-activated package.
  final bool isGlobal;

  /// The lockfile for the entrypoint.
  ///
  /// If not provided to the entrypoint, it will be loaded lazily from disk.
  LockFile get lockFile {
    if (_lockFile != null) return _lockFile;

    if (!fileExists(lockFilePath)) {
      _lockFile = LockFile.empty();
    } else {
      _lockFile = LockFile.load(lockFilePath, cache.sources);
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
    var packages = {
      for (var id in lockFile.packages.values) id.name: cache.load(id)
    };
    packages[root.name] = root;

    _packageGraph = PackageGraph(this, lockFile, packages);
    return _packageGraph;
  }

  PackageGraph _packageGraph;

  /// The path to the entrypoint's "packages" directory.
  String get packagesPath => root.path('packages');

  /// The path to the entrypoint's ".packages" file.
  String get packagesFile => root.path('.packages');

  /// The path to the entrypoint's ".dart_tool/package_config.json" file.
  String get packageConfigFile =>
      root.path('.dart_tool', 'package_config.json');

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

  /// Loads the entrypoint for the package at the current directory.
  Entrypoint.current(this.cache)
      : root = Package.load(null, '.', cache.sources, isRootPackage: true),
        _inMemory = false,
        isGlobal = false;

  /// Loads the entrypoint from a package at [rootDir].
  Entrypoint(String rootDir, this.cache)
      : root = Package.load(null, rootDir, cache.sources, isRootPackage: true),
        _inMemory = false,
        isGlobal = true;

  /// Creates an entrypoint given package and lockfile objects.
  Entrypoint.inMemory(this.root, this._lockFile, this.cache)
      : _inMemory = true,
        isGlobal = true;

  /// Creates an entrypoint given a package and a [solveResult], from which the
  /// package graph and lockfile will be computed.
  Entrypoint.fromSolveResult(this.root, this.cache, SolveResult solveResult)
      : _inMemory = true,
        isGlobal = true {
    _packageGraph = PackageGraph.fromSolveResult(this, solveResult);
    _lockFile = _packageGraph.lockFile;
  }

  /// Writes .packages and .dart_tool/package_config.json
  Future<void> writePackagesFiles() async {
    writeTextFile(packagesFile, lockFile.packagesFile(cache, root.name));
    ensureDir(p.dirname(packageConfigFile));
    writeTextFile(
        packageConfigFile,
        await lockFile.packageConfigFile(
          cache,
          entrypoint: root.name,
          entrypointSdkConstraint: root.pubspec.sdkConstraints[sdk.identifier],
        ));
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
  /// Updates [lockFile] and [packageRoot] accordingly.
  Future acquireDependencies(SolveType type,
      {List<String> useLatest,
      bool dryRun = false,
      bool precompile = false}) async {
    var result = await log.progress(
      'Resolving dependencies',
      () => resolveVersions(
        type,
        cache,
        root,
        lockFile: lockFile,
        useLatest: useLatest,
      ),
    );

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
            'for the following packages:\n\n$overriddenPackages\n\n'
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

    await Future.wait(result.packages.map(_get));
    _saveLockFile(result);

    result.summarizeChanges(type, dryRun: dryRun);

    /// Build a package graph from the version solver results so we don't
    /// have to reload and reparse all the pubspecs.
    _packageGraph = PackageGraph.fromSolveResult(this, result);

    await writePackagesFiles();

    try {
      if (precompile) {
        await precompileExecutables(changed: result.changedPackages);
      } else {
        _deleteExecutableSnapshots(changed: result.changedPackages);
      }
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

    await log.progress('Precompiling executables', () async {
      ensureDir(_snapshotPath);

      // Make sure there's a trailing newline so our version file matches the
      // SDK's.
      writeTextFile(p.join(_snapshotPath, 'sdk-version'), '${sdk.version}\n');

      await _precompileExecutables(executables);
    });
  }

  //// Precompiles [executables] to snapshots from the filesystem.
  Future<void> _precompileExecutables(Map<String, List<String>> executables) {
    return waitAndPrintErrors(executables.keys.map((package) {
      var dir = p.join(_snapshotPath, package);
      cleanDir(dir);
      return waitAndPrintErrors(executables[package]
          .map((path) => _precompileExecutable(package, path)));
    }));
  }

  /// Precompiles executable .dart file at [path] to a snapshot.
  Future<void> precompileExecutable(String package, String path) async {
    return await log.progress('Precompiling executable', () async {
      var dir = p.join(_snapshotPath, package);
      ensureDir(dir);
      return waitAndPrintErrors([_precompileExecutable(package, path)]);
    });
  }

  Future<void> _precompileExecutable(String package, String path) async {
    var dir = p.join(_snapshotPath, package);
    var url = p.toUri(p.join(packageGraph.packages[package].dir, path));
    await dart.snapshot(url, p.join(dir, p.basename(path) + '.snapshot.dart2'),
        packagesFile: p.toUri(packagesFile),
        name: '$package:${p.basenameWithoutExtension(path)}');
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
        readTextFile(sdkVersionPath) != '${sdk.version}\n') {
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
    var executablesExist = executables.every((executable) {
      var snapshotPath = p.join(_snapshotPath, packageName,
          '${p.basename(executable)}.snapshot.dart2');
      return fileExists(snapshotPath);
    });
    if (!executablesExist) return executables;

    // Otherwise, we don't need to recompile.
    return [];
  }

  /// Makes sure the package at [id] is locally available.
  ///
  /// This automatically downloads the package to the system-wide cache as well
  /// if it requires network access to retrieve (specifically, if the package's
  /// source is a [CachedSource]).
  Future _get(PackageId id) {
    return http.withDependencyType(root.dependencyType(id.name), () async {
      if (id.isRoot) return;

      var source = cache.source(id.source);
      if (source is CachedSource) await source.downloadToSystemCache(id);
    });
  }

  /// Throws a [DataError] if the `.packages` file or the
  /// `.dart_tool/package_config.json` file doesn't exist or if it's out-of-date
  /// relative to the lockfile or the pubspec.
  void assertUpToDate() {
    if (_inMemory) return;

    if (!entryExists(lockFilePath)) {
      dataError('No pubspec.lock file found, please run "pub get" first.');
    }
    if (!entryExists(packageConfigFile)) {
      dataError(
        'No .dart_tool/package_config.json file found, please run "pub get" '
        'first.\n\n'
        'Starting with Dart 2.7 this file configures the resolution of '
        'package import URIs. Running "pub get" will generate this file.',
      );
    }
    if (!entryExists(packagesFile)) {
      dataError('No .packages file found, please run "pub get" first.');
    }

    // Manually parse the lockfile because a full YAML parse is relatively slow
    // and this is on the hot path for "pub run".
    var lockFileText = readTextFile(lockFilePath);
    var hasPathDependencies = lockFileText.contains('\n    source: path\n');

    var pubspecModified = File(pubspecPath).lastModifiedSync();
    var lockFileModified = File(lockFilePath).lastModifiedSync();

    var touchedLockFile = false;
    if (lockFileModified.isBefore(pubspecModified) || hasPathDependencies) {
      // If `pubspec.lock` is newer than `pubspec.yaml` or we have path
      // dependencies, then we check that `pubspec.lock` is a correct solution
      // for the requirements in `pubspec.yaml`. This aims to:
      //  * Prevent missing packages when `pubspec.lock` is checked into git.
      //  * Mitigate missing transitive dependencies when the `pubspec.yaml` in
      //    a path dependency is changed.
      _assertLockFileUpToDate();
      if (_arePackagesAvailable()) {
        touchedLockFile = true;
        touch(lockFilePath);
      } else {
        dataError('The pubspec.yaml file has changed since the pubspec.lock '
            'file was generated, please run "pub get" again.');
      }
    }

    var packagesModified = File(packagesFile).lastModifiedSync();
    if (packagesModified.isBefore(lockFileModified)) {
      _checkPackagesFileUpToDate();
      touch(packagesFile);
    } else if (touchedLockFile) {
      touch(packagesFile);
    }

    var packageConfigModified = File(packageConfigFile).lastModifiedSync();
    if (packageConfigModified.isBefore(lockFileModified) ||
        hasPathDependencies) {
      // If `package_config.json` is newer than `pubspec.lock` or we have
      // path dependencies, then we check that `package_config.json` is a
      // correct configuration on the local machine. This aims to:
      //  * Mitigate issues when copying a folder from one machine to another.
      //  * Force `pub get` if a path dependency has changed language verison.
      _checkPackageConfigUpToDate();
      touch(packageConfigFile);
    } else if (touchedLockFile) {
      touch(packageConfigFile);
    }

    for (var match in _sdkConstraint.allMatches(lockFileText)) {
      var identifier = match[1] == 'sdk' ? 'dart' : match[1].trim();
      var sdk = sdks[identifier];

      // Don't complain if there's an SDK constraint for an unavailable SDK. For
      // example, the Flutter SDK being unavailable just means that we aren't
      // running from within the `flutter` executable, and we want users to be
      // able to `pub run` non-Flutter tools even in a Flutter app.
      if (!sdk.isAvailable) continue;

      var parsedConstraint = VersionConstraint.parse(match[2]);
      if (!parsedConstraint.allows(sdk.version)) {
        dataError('${sdk.name} ${sdk.version} is incompatible with your '
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

    var overrides = MapKeySet(root.dependencyOverrides);

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
      return dirExists(dir) && fileExists(p.join(dir, 'pubspec.yaml'));
    });
  }

  /// Determines [lockFile] agrees with the given [packagePathsMapping].
  ///
  /// The [packagePathsMapping] is a mapping from package names to paths where
  /// the packages are located. (The library is located under
  /// `lib/` relative to the path given).
  bool _isPackagePathsMappingUpToDateWithLockfile(
    Map<String, String> packagePathsMapping,
  ) {
    // Check that [packagePathsMapping] does not contain more packages than what
    // is required. This could lead to import statements working, when they are
    // not supposed to work.
    final hasExtraMappings = packagePathsMapping.keys.every((packageName) {
      return packageName == root.name ||
          lockFile.packages.containsKey(packageName);
    });
    if (!hasExtraMappings) {
      return false;
    }

    // Check that all packages in the [lockFile] are reflected in the
    // [packagePathsMapping].
    return lockFile.packages.values.every((lockFileId) {
      // It's very unlikely that the lockfile is invalid here, but it's not
      // impossible—for example, the user may have a very old application
      // package with a checked-in lockfile that's newer than the pubspec, but
      // that contains SDK dependencies.
      if (lockFileId.source is UnknownSource) return false;

      final packagePath = packagePathsMapping[lockFileId.name];
      if (packagePath == null) {
        return false;
      }

      final source = cache.source(lockFileId.source);
      final lockFilePackagePath =
          p.join(root.dir, source.getDirectory(lockFileId));

      // Make sure that the packagePath agrees with the lock file about the
      // path to the package.
      if (p.normalize(packagePath) != p.normalize(lockFilePackagePath)) {
        return false;
      }

      // For cached sources, make sure the directory exists and looks like a
      // package. This is also done by [_arePackagesAvailable] but that may not
      // be run if the lockfile is newer than the pubspec.
      if (source is CachedSource && !dirExists(lockFilePackagePath) ||
          !fileExists(p.join(lockFilePackagePath, 'pubspec.yaml'))) {
        return false;
      }

      return true;
    });
  }

  /// Checks whether or not the `.packages` file is out of date with respect
  /// to the [lockfile].
  ///
  /// This will throw a [DataError] if [lockfile] contains dependencies that
  /// are not in the `.packages` or that don't match what's in there.
  void _checkPackagesFileUpToDate() {
    void outOfDate() {
      dataError('The pubspec.lock file has changed since the .packages file '
          'was generated, please run "pub get" again.');
    }

    var packages = packages_file.parse(
        File(packagesFile).readAsBytesSync(), p.toUri(packagesFile));

    final packagePathsMapping = <String, String>{};
    for (final package in packages.keys) {
      final packageUri = packages[package];

      // Pub only generates "file:" and relative URIs.
      if (packageUri.scheme != 'file' && packageUri.scheme.isNotEmpty) {
        outOfDate();
      }

      // Get the dirname of the .packages path, since it's pointing to lib/.
      final packagePath = p.dirname(p.join(root.dir, p.fromUri(packageUri)));
      packagePathsMapping[package] = packagePath;
    }

    if (!_isPackagePathsMappingUpToDateWithLockfile(packagePathsMapping)) {
      outOfDate();
    }
  }

  /// Checks whether or not the `.dart_tool/package_config.json` file is
  /// out of date with respect to the lockfile.
  ///
  /// This will throw a [DataError] if the [lockfile] contains dependencies that
  /// are not in the `.dart_tool/package_config.json` or that don't match
  /// what's in there.
  ///
  /// Throws [DataException], if `.dart_tool/package_config.json` is not
  /// up-to-date for some other reason.
  void _checkPackageConfigUpToDate() {
    void outOfDate() {
      dataError('The pubspec.lock file has changed since the '
          '.dart_tool/package_config.json file '
          'was generated, please run "pub get" again.');
    }

    void badPackageConfig() {
      dataError(
          'The ".dart_tool/package_config.json" file is not recognized by '
          '"pub" version, please run "pub get".');
    }

    String packageConfigRaw;
    try {
      packageConfigRaw = readTextFile(packageConfigFile);
    } on FileException {
      dataError(
          'The ".dart_tool/package_config.json" file does not exist, please run "pub get".');
    }

    PackageConfig cfg;
    try {
      cfg = PackageConfig.fromJson(json.decode(packageConfigRaw));
    } on FormatException {
      badPackageConfig();
    }

    // Version 2 is the initial version number for `package_config.json`,
    // because `.packages` was version 1 (even if it was a different file).
    // If the version is different from 2, then it must be a newer incompatible
    // version, hence, the user should run `pub get` with the downgraded SDK.
    if (cfg.configVersion != 2) {
      badPackageConfig();
    }

    final packagePathsMapping = <String, String>{};
    for (final pkg in cfg.packages) {
      // Pub always sets packageUri = lib/
      if (pkg.packageUri == null || pkg.packageUri.toString() != 'lib/') {
        badPackageConfig();
      }
      packagePathsMapping[pkg.name] =
          root.path('.dart_tool', p.fromUri(pkg.rootUri));
    }
    if (!_isPackagePathsMappingUpToDateWithLockfile(packagePathsMapping)) {
      outOfDate();
    }

    // Check if language version specified in the `package_config.json` is
    // correct. This is important for path dependencies as these can mutate.
    for (final pkg in cfg.packages) {
      final id = lockFile.packages[pkg.name];
      if (id == null) {
        assert(
          false,
          'unnecessary package_config.json entries should be forbidden by '
          '_isPackagePathsMappingUpToDateWithLockfile',
        );
        continue;
      }

      // If a package is cached, then it's universally immutable and we need
      // not check if the language version is correct.
      final source = cache.source(id.source);
      if (source is CachedSource) {
        continue;
      }

      try {
        // Load `pubspec.yaml` and extract language version to compare with the
        // language version from `package_config.json`.
        final languageVersion = extractLanguageVersion(
          cache.load(id).pubspec.sdkConstraints[sdk.identifier],
        );
        if (pkg.languageVersion != languageVersion) {
          dataError('${p.join(source.getDirectory(id), 'pubspec.yaml')} has '
              'changed since the pubspec.lock file was generated, please run '
              '"pub get" again.');
        }
      } on FileException {
        dataError('Failed to read pubspec.yaml for "${pkg.name}", perhaps the '
            'entry is missing, please run "pub get".');
      }
    }
  }

  /// Saves a list of concrete package versions to the `pubspec.lock` file.
  void _saveLockFile(SolveResult result) {
    _lockFile = result.lockFile;
    var lockFilePath = root.path('pubspec.lock');
    writeTextFile(lockFilePath, _lockFile.serialize(root.dir));
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
}
