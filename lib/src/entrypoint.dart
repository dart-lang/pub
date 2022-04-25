// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:pool/pool.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

import 'command_runner.dart';
import 'dart.dart' as dart;
import 'exceptions.dart';
import 'executable.dart';
import 'io.dart';
import 'language_version.dart';
import 'lock_file.dart';
import 'log.dart' as log;
import 'package.dart';
import 'package_config.dart';
import 'package_config.dart' show PackageConfig;
import 'package_graph.dart';
import 'package_name.dart';
import 'packages_file.dart' as packages_file;
import 'pub_embeddable_command.dart';
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
  ///
  /// For a global package, this is the activated package.
  final Package root;

  /// For a global package, this is the directory that the package is installed
  /// in. Non-global packages have null.
  final String? globalDir;

  /// The system-wide cache which caches packages that need to be fetched over
  /// the network.
  final SystemCache cache;

  /// Whether this entrypoint exists within the package cache.
  bool get isCached => !root.isInMemory && p.isWithin(cache.rootDir, root.dir);

  /// Whether this is an entrypoint for a globally-activated package.
  // final bool isGlobal;
  bool get isGlobal => globalDir != null;

  /// The lockfile for the entrypoint.
  ///
  /// If not provided to the entrypoint, it will be loaded lazily from disk.
  LockFile get lockFile => _lockFile ??= _loadLockFile();

  LockFile _loadLockFile() {
    if (!fileExists(lockFilePath)) {
      return _lockFile = LockFile.empty();
    } else {
      return _lockFile = LockFile.load(lockFilePath, cache.sources);
    }
  }

  LockFile? _lockFile;

  /// The package graph for the application and all of its transitive
  /// dependencies.
  ///
  /// Throws a [DataError] if the `.dart_tool/package_config.json` file isn't
  /// up-to-date relative to the pubspec and the lockfile.
  PackageGraph get packageGraph => _packageGraph ??= _createPackageGraph();

  PackageGraph _createPackageGraph() {
    assertUpToDate();
    var packages = {
      for (var id in lockFile.packages.values) id.name: cache.load(id)
    };
    packages[root.name] = root;

    return PackageGraph(this, lockFile, packages);
  }

  PackageGraph? _packageGraph;

  /// Where the lock file and package configurations are to be found.
  ///
  /// Global packages (except those from path source)
  /// store these in the global cache.
  String? get _configRoot => isCached ? globalDir : root.dir;

  /// The path to the entrypoint's ".packages" file.
  ///
  /// This file is being slowly deprecated in favor of
  /// `.dart_tool/package_config.json`. Pub will still create it, but will
  /// not require it or make use of it within pub.
  String get packagesFile => p.normalize(p.join(_configRoot!, '.packages'));

  /// The path to the entrypoint's ".dart_tool/package_config.json" file.
  String get packageConfigFile =>
      p.normalize(p.join(_configRoot!, '.dart_tool', 'package_config.json'));

  /// The path to the entrypoint package's pubspec.
  String get pubspecPath => p.normalize(root.path('pubspec.yaml'));

  /// Whether the entrypoint package contains a `pubspec_overrides.yaml` file.
  bool get hasPubspecOverrides =>
      !root.isInMemory && fileExists(pubspecOverridesPath);

  /// The path to the entrypoint package's pubspec overrides file.
  String get pubspecOverridesPath =>
      p.normalize(root.path('pubspec_overrides.yaml'));

  /// The path to the entrypoint package's lockfile.
  String get lockFilePath => p.normalize(p.join(_configRoot!, 'pubspec.lock'));

  /// The path to the entrypoint package's `.dart_tool/pub` cache directory.
  ///
  /// If the old-style `.pub` directory is being used, this returns that
  /// instead.
  ///
  /// For globally activated packages from path, this is not the same as
  /// [configRoot], because the snapshots should be stored in the global cache,
  /// but the configuration is stored at the package itself.
  String get cachePath {
    if (isGlobal) {
      return globalDir!;
    } else {
      var newPath = root.path('.dart_tool/pub');
      var oldPath = root.path('.pub');
      if (!dirExists(newPath) && dirExists(oldPath)) return oldPath;
      return newPath;
    }
  }

  /// The path to the directory containing dependency executable snapshots.
  String get _snapshotPath => p.join(cachePath, 'bin');

  /// The path to the directory containing previous dill files for incremental
  /// builds.
  String get _incrementalDillsPath => p.join(cachePath, 'incremental');

  /// Loads the entrypoint from a package at [rootDir].
  Entrypoint(
    String rootDir,
    this.cache,
  )   : root = Package.load(null, rootDir, cache.sources,
            withPubspecOverrides: true),
        globalDir = null;

  Entrypoint.inMemory(this.root, this.cache,
      {required LockFile? lockFile, SolveResult? solveResult})
      : _lockFile = lockFile,
        globalDir = null {
    if (solveResult != null) {
      _packageGraph = PackageGraph.fromSolveResult(this, solveResult);
    }
  }

  /// Creates an entrypoint given package and lockfile objects.
  /// If a SolveResult is already created it can be passed as an optimization.
  Entrypoint.global(this.globalDir, this.root, this._lockFile, this.cache,
      {SolveResult? solveResult}) {
    if (solveResult != null) {
      _packageGraph = PackageGraph.fromSolveResult(this, solveResult);
    }
  }

  /// Gets the [Entrypoint] package for the current working directory.
  ///
  /// This will be null if the example folder doesn't have a `pubspec.yaml`.
  Entrypoint? get example {
    if (_example != null) return _example;
    if (!fileExists(root.path('example', 'pubspec.yaml'))) {
      return null;
    }
    return _example = Entrypoint(root.path('example'), cache);
  }

  Entrypoint? _example;

  /// Writes .packages and .dart_tool/package_config.json
  Future<void> writePackagesFiles() async {
    final entrypointName = isGlobal ? null : root.name;
    writeTextFile(
        packagesFile,
        lockFile.packagesFile(cache,
            entrypoint: entrypointName,
            relativeFrom: isGlobal ? null : root.dir));
    ensureDir(p.dirname(packageConfigFile));
    writeTextFile(
        packageConfigFile,
        await lockFile.packageConfigFile(cache,
            entrypoint: entrypointName,
            entrypointSdkConstraint:
                root.pubspec.sdkConstraints[sdk.identifier],
            relativeFrom: isGlobal ? null : root.dir));
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
  /// if [onlyReportSuccessOrFailure] is `true` only success or failure will be shown ---
  /// in case of failure, a reproduction command is shown.
  ///
  /// Updates [lockFile] and [packageRoot] accordingly.
  Future<void> acquireDependencies(
    SolveType type, {
    Iterable<String>? unlock,
    bool dryRun = false,
    bool precompile = false,
    required PubAnalytics? analytics,
    bool onlyReportSuccessOrFailure = false,
  }) async {
    if (!onlyReportSuccessOrFailure && hasPubspecOverrides) {
      log.warning(
          'Warning: pubspec.yaml has overrides from $pubspecOverridesPath');
    }

    final suffix = root.isInMemory || root.dir == '.' ? '' : ' in ${root.dir}';
    SolveResult result;
    try {
      result = await log.progress('Resolving dependencies$suffix', () async {
        _checkSdkConstraint(root.pubspec);
        return resolveVersions(
          type,
          cache,
          root,
          lockFile: lockFile,
          unlock: unlock ?? [],
        );
      });
    } catch (e) {
      if (onlyReportSuccessOrFailure && (e is ApplicationException)) {
        final directoryOption = root.isInMemory || root.dir == '.'
            ? ''
            : ' --directory ${root.dir}';
        throw ApplicationException(
            'Resolving dependencies$suffix failed. For details run `$topLevelProgram pub ${type.toString()}$directoryOption`');
      } else {
        rethrow;
      }
    }

    // Log once about all overridden packages.
    if (warnAboutPreReleaseSdkOverrides) {
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

    if (!onlyReportSuccessOrFailure) {
      await result.showReport(type, cache);
    }
    if (!dryRun) {
      await result.downloadCachedPackages(cache);
      saveLockFile(result);
    }
    if (onlyReportSuccessOrFailure) {
      log.message('Got dependencies$suffix.');
    } else {
      await result.summarizeChanges(type, cache, dryRun: dryRun);
    }

    if (!dryRun) {
      if (analytics != null) {
        result.sendAnalytics(analytics);
      }

      /// Build a package graph from the version solver results so we don't
      /// have to reload and reparse all the pubspecs.
      _packageGraph = PackageGraph.fromSolveResult(this, result);

      await writePackagesFiles();

      try {
        if (precompile) {
          await precompileExecutables();
        } else {
          _deleteExecutableSnapshots(changed: result.changedPackages);
        }
      } catch (error, stackTrace) {
        // Just log exceptions here. Since the method is just about acquiring
        // dependencies, it shouldn't fail unless that fails.
        log.exception(error, stackTrace);
      }
    }
  }

  /// All executables that should be snapshotted from this entrypoint.
  ///
  /// This is all executables in direct dependencies.
  /// that don't transitively depend on [this] or on a mutable dependency.
  ///
  /// Except globally activated packages they should precompile executables from
  /// the package itself if they are immutable.
  List<Executable> get _builtExecutables {
    if (isGlobal) {
      if (isCached) {
        return root.executablePaths
            .map((path) => Executable(root.name, path))
            .toList();
      } else {
        return <Executable>[];
      }
    }
    final r = root.immediateDependencies.keys.expand((packageName) {
      final package = packageGraph.packages[packageName]!;
      return package.executablePaths
          .map((path) => Executable(packageName, path));
    }).toList();
    return r;
  }

  /// Precompiles all [_builtExecutables].
  Future<void> precompileExecutables() async {
    migrateCache();

    final executables = _builtExecutables;

    if (executables.isEmpty) return;

    await log.progress('Building package executables', () async {
      if (isGlobal) {
        /// Global snapshots might linger in the cache if we don't remove old
        /// snapshots when it is re-activated.
        cleanDir(_snapshotPath);
      } else {
        ensureDir(_snapshotPath);
      }
      // Don't do more than `Platform.numberOfProcessors - 1` compilations
      // concurrently. Though at least one.
      final pool = Pool(max(Platform.numberOfProcessors - 1, 1));
      return waitAndPrintErrors(executables.map((executable) async {
        await pool.withResource(() async {
          return _precompileExecutable(executable);
        });
      }));
    });
  }

  /// Precompiles executable .dart file at [path] to a snapshot.
  Future<void> precompileExecutable(Executable executable) async {
    await log.progress('Building package executable', () async {
      ensureDir(p.dirname(pathOfExecutable(executable)));
      return waitAndPrintErrors([_precompileExecutable(executable)]);
    });
  }

  Future<void> _precompileExecutable(Executable executable) async {
    final package = executable.package;

    await dart.precompile(
        executablePath: resolveExecutable(executable),
        outputPath: pathOfExecutable(executable),
        incrementalDillPath: incrementalDillPathOfExecutable(executable),
        packageConfigPath: packageConfigFile,
        name:
            '$package:${p.basenameWithoutExtension(executable.relativePath)}');
  }

  /// The location of the snapshot of the dart program at [path] in [package]
  /// will be stored here.
  ///
  /// We use the sdk version to make sure we don't run snapshots from a
  /// different sdk.
  ///
  /// [path] must be relative.
  String pathOfExecutable(Executable executable) {
    assert(p.isRelative(executable.relativePath));
    final versionSuffix = sdk.version;
    return isGlobal
        ? p.join(_snapshotPath,
            '${p.basename(executable.relativePath)}-$versionSuffix.snapshot')
        : p.join(_snapshotPath, executable.package,
            '${p.basename(executable.relativePath)}-$versionSuffix.snapshot');
  }

  String incrementalDillPathOfExecutable(Executable executable) {
    assert(p.isRelative(executable.relativePath));
    return isGlobal
        ? p.join(_incrementalDillsPath,
            '${p.basename(executable.relativePath)}.incremental.dill')
        : p.join(_incrementalDillsPath, executable.package,
            '${p.basename(executable.relativePath)}.incremental.dill');
  }

  /// The absolute path of [executable] resolved relative to [this].
  String resolveExecutable(Executable executable) {
    return p.join(
      packageGraph.packages[executable.package]!.dir,
      executable.relativePath,
    );
  }

  /// Deletes outdated cached executable snapshots.
  ///
  /// If [changed] is passed, only dependencies whose contents might be changed
  /// if one of the given packages changes will have their executables deleted.
  void _deleteExecutableSnapshots({Iterable<String>? changed}) {
    if (!dirExists(_snapshotPath)) return;

    // If we don't know what changed, we can't safely re-use any snapshots.
    if (changed == null) {
      deleteEntry(_snapshotPath);
      return;
    }
    var changedDeps = changed;
    changedDeps = changedDeps.toSet();

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
              .any((dep) => changedDeps.contains(dep.name))) {
        deleteEntry(entry);
      }
    }
  }

  /// Throws a [DataError] if the `.dart_tool/package_config.json` file doesn't
  /// exist or if it's out-of-date relative to the lockfile or the pubspec.
  ///
  /// A `.packages` file is not required. But if it exists it is checked for
  /// consistency with the pubspec.lock.
  void assertUpToDate() {
    if (isCached) return;

    if (!entryExists(lockFilePath)) {
      dataError(
          'No $lockFilePath file found, please run "$topLevelProgram pub get" first.');
    }
    if (!entryExists(packageConfigFile)) {
      dataError(
        'No $packageConfigFile file found, please run "$topLevelProgram pub get".\n'
        '\n'
        'Starting with Dart 2.7, the package_config.json file configures '
        'resolution of package import URIs; run "$topLevelProgram pub get" to generate it.',
      );
    }

    // Manually parse the lockfile because a full YAML parse is relatively slow
    // and this is on the hot path for "pub run".
    var lockFileText = readTextFile(lockFilePath);
    var hasPathDependencies = lockFileText.contains('\n    source: path\n');

    var pubspecModified = File(pubspecPath).lastModifiedSync();
    var lockFileModified = File(lockFilePath).lastModifiedSync();

    var pubspecChanged = lockFileModified.isBefore(pubspecModified);
    var pubspecOverridesChanged = false;

    if (hasPubspecOverrides) {
      var pubspecOverridesModified =
          File(pubspecOverridesPath).lastModifiedSync();
      pubspecOverridesChanged =
          lockFileModified.isBefore(pubspecOverridesModified);
    }

    var touchedLockFile = false;
    if (pubspecChanged || pubspecOverridesChanged || hasPathDependencies) {
      // If `pubspec.lock` is older than `pubspec.yaml` or
      // `pubspec_overrides.yaml`, or we have path dependencies, then we check
      // that `pubspec.lock` is a correct solution for the requirements in
      // `pubspec.yaml` and `pubspec_overrides.yaml`. This aims to:
      //  * Prevent missing packages when `pubspec.lock` is checked into git.
      //  * Mitigate missing transitive dependencies when the `pubspec.yaml` in
      //    a path dependency is changed.
      _assertLockFileUpToDate();
      if (_arePackagesAvailable()) {
        touchedLockFile = true;
        touch(lockFilePath);
      } else {
        var filePath = pubspecChanged ? pubspecPath : pubspecOverridesPath;
        dataError('The $filePath file has changed since the $lockFilePath '
            'file was generated, please run "$topLevelProgram pub get" again.');
      }
    }

    if (fileExists(packagesFile)) {
      var packagesModified = File(packagesFile).lastModifiedSync();
      if (packagesModified.isBefore(lockFileModified)) {
        _checkPackagesFileUpToDate();
        touch(packagesFile);
      } else if (touchedLockFile) {
        touch(packagesFile);
      }
    }

    var packageConfigModified = File(packageConfigFile).lastModifiedSync();
    if (packageConfigModified.isBefore(lockFileModified) ||
        hasPathDependencies) {
      // If `package_config.json` is older than `pubspec.lock` or we have
      // path dependencies, then we check that `package_config.json` is a
      // correct configuration on the local machine. This aims to:
      //  * Mitigate issues when copying a folder from one machine to another.
      //  * Force `pub get` if a path dependency has changed language version.
      _checkPackageConfigUpToDate();
      touch(packageConfigFile);
    } else if (touchedLockFile) {
      touch(packageConfigFile);
    }

    for (var match in _sdkConstraint.allMatches(lockFileText)) {
      var identifier = match[1] == 'sdk' ? 'dart' : match[1]!.trim();
      var sdk = sdks[identifier]!;

      // Don't complain if there's an SDK constraint for an unavailable SDK. For
      // example, the Flutter SDK being unavailable just means that we aren't
      // running from within the `flutter` executable, and we want users to be
      // able to `pub run` non-Flutter tools even in a Flutter app.
      if (!sdk.isAvailable) continue;

      var parsedConstraint = VersionConstraint.parse(match[2]!);
      if (!parsedConstraint.allows(sdk.version!)) {
        dataError('${sdk.name} ${sdk.version} is incompatible with your '
            "dependencies' SDK constraints. Please run \"$topLevelProgram pub get\" again.");
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
      dataError(
          'The $pubspecPath file has changed since the $lockFilePath file '
          'was generated, please run "$topLevelProgram pub get" again.');
    }

    var overrides = MapKeySet(root.dependencyOverrides);

    // Check that uncached dependencies' pubspecs are also still satisfied,
    // since they're mutable and may have changed since the last get.
    for (var id in lockFile.packages.values) {
      final source = id.source;
      if (source is CachedSource) continue;

      try {
        if (cache.load(id).dependencies.values.every((dep) =>
            overrides.contains(dep.name) || _isDependencyUpToDate(dep))) {
          continue;
        }
      } on FileException {
        // If we can't load the pubspec, the user needs to re-run "pub get".
      }

      final relativePubspecPath =
          p.join(cache.getDirectory(id, relativeFrom: '.'), 'pubspec.yaml');
      dataError('$relativePubspecPath has '
          'changed since the $lockFilePath file was generated, please run '
          '"$topLevelProgram pub get" again.');
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
      var source = package.source;
      if (source is! CachedSource) return true;

      // Get the directory.
      var dir = cache.getDirectory(package, relativeFrom: '.');
      // See if the directory is there and looks like a package.
      return fileExists(p.join(dir, 'pubspec.yaml'));
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
    final hasExtraMappings = !packagePathsMapping.keys.every((packageName) {
      return packageName == root.name ||
          lockFile.packages.containsKey(packageName);
    });
    if (hasExtraMappings) {
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

      final source = lockFileId.source;
      final lockFilePackagePath = root.path(
        cache.getDirectory(lockFileId, relativeFrom: root.dir),
      );

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
      dataError('The $lockFilePath file has changed since the .packages file '
          'was generated, please run "$topLevelProgram pub get" again.');
    }

    var packages = packages_file.parse(
        File(packagesFile).readAsBytesSync(), p.toUri(packagesFile));

    final packagePathsMapping = <String, String>{};
    for (final package in packages.keys) {
      final packageUri = packages[package]!;

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
      dataError('The $lockFilePath file has changed since the '
          '$packageConfigFile file '
          'was generated, please run "$topLevelProgram pub get" again.');
    }

    void badPackageConfig() {
      dataError('The "$packageConfigFile" file is not recognized by '
          '"pub" version, please run "$topLevelProgram pub get".');
    }

    late String packageConfigRaw;
    try {
      packageConfigRaw = readTextFile(packageConfigFile);
    } on FileException {
      dataError(
          'The "$packageConfigFile" file does not exist, please run "$topLevelProgram pub get".');
    }

    late PackageConfig cfg;
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

    // We allow the package called 'flutter_gen' to be injected into
    // package_config.
    //
    // This is somewhat a hack. But it allows flutter to generate code in a
    // package as it likes.
    //
    // See https://github.com/flutter/flutter/issues/73870 .
    final packagesToCheck =
        cfg.packages.where((package) => package.name != 'flutter_gen');
    for (final pkg in packagesToCheck) {
      // Pub always makes a packageUri of lib/
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
      if (pkg.name == root.name || pkg.name == 'flutter_gen') continue;
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
      final source = id.source;
      if (source is CachedSource) {
        continue;
      }

      try {
        // Load `pubspec.yaml` and extract language version to compare with the
        // language version from `package_config.json`.
        final languageVersion = LanguageVersion.fromSdkConstraint(
          cache.load(id).pubspec.sdkConstraints[sdk.identifier],
        );
        if (pkg.languageVersion != languageVersion) {
          final relativePubspecPath = p.join(
            cache.getDirectory(id, relativeFrom: '.'),
            'pubspec.yaml',
          );
          dataError('$relativePubspecPath has '
              'changed since the $lockFilePath file was generated, please run '
              '"$topLevelProgram pub get" again.');
        }
      } on FileException {
        dataError('Failed to read pubspec.yaml for "${pkg.name}", perhaps the '
            'entry is missing, please run "$topLevelProgram pub get".');
      }
    }
  }

  /// Saves a list of concrete package versions to the `pubspec.lock` file.
  ///
  /// Will use Windows line endings (`\r\n`) if a `pubspec.lock` exists, and
  /// uses that.
  void saveLockFile(SolveResult result) {
    _lockFile = result.lockFile;

    final windowsLineEndings = fileExists(lockFilePath) &&
        detectWindowsLineEndings(readTextFile(lockFilePath));

    final serialized = lockFile.serialize(root.dir);
    writeTextFile(lockFilePath,
        windowsLineEndings ? serialized.replaceAll('\n', '\r\n') : serialized);
  }

  /// If the entrypoint uses the old-style `.pub` cache directory, migrates it
  /// to the new-style `.dart_tool/pub` directory.
  void migrateCache() {
    // Cached packages don't have these.
    if (isCached) return;

    var oldPath = p.join(_configRoot!, '.pub');
    if (!dirExists(oldPath)) return;

    var newPath = root.path('.dart_tool/pub');

    // If both the old and new directories exist, something weird is going on.
    // Do nothing to avoid making things worse. Pub will prefer the new
    // directory anyway.
    if (dirExists(newPath)) return;

    ensureDir(p.dirname(newPath));
    renameDir(oldPath, newPath);
  }

  /// We require an SDK constraint lower-bound as of Dart 2.12.0
  ///
  /// We don't allow unknown sdks.
  void _checkSdkConstraint(Pubspec pubspec) {
    final dartSdkConstraint = pubspec.sdkConstraints['dart'];
    if (dartSdkConstraint is! VersionRange || dartSdkConstraint.min == null) {
      // Suggest version range '>=2.10.0 <3.0.0', we avoid using:
      // [CompatibleWithVersionRange] because some pub versions don't support
      // caret syntax (e.g. '^2.10.0')
      var suggestedConstraint = VersionRange(
        min: Version.parse('2.10.0'),
        max: Version.parse('2.10.0').nextBreaking,
        includeMin: true,
      );
      // But if somehow that doesn't work, we fallback to safe sanity, mostly
      // important for tests, or if we jump to 3.x without patching this code.
      if (!suggestedConstraint.allows(sdk.version)) {
        suggestedConstraint = VersionRange(
          min: sdk.version,
          max: sdk.version.nextBreaking,
          includeMin: true,
        );
      }
      throw DataException('''
$pubspecPath has no lower-bound SDK constraint.
You should edit $pubspecPath to contain an SDK constraint:

environment:
  sdk: '$suggestedConstraint'

See https://dart.dev/go/sdk-constraint
''');
    }
    for (final sdk in pubspec.sdkConstraints.keys) {
      if (!sdks.containsKey(sdk)) {
        final environment = pubspec.fields.nodes['environment'] as YamlMap;
        final keyNode = environment.nodes.entries
            .firstWhere((e) => (e.key as YamlNode).value == sdk)
            .key as YamlNode;
        throw PubspecException('''
$pubspecPath refers to an unknown sdk '$sdk'.

Did you mean to add it as a dependency?

Either remove the constraint, or upgrade to a version of pub that supports the
given sdk.

See https://dart.dev/go/sdk-constraint
''', keyNode.span);
      }
    }
  }
}

/// Returns `true` if the [text] looks like it uses windows line endings.
///
/// The heuristic used is to count all `\n` in the text and if stricly more than
/// half of them are preceded by `\r` we report `true`.
@visibleForTesting
bool detectWindowsLineEndings(String text) {
  var index = -1;
  var unixNewlines = 0;
  var windowsNewlines = 0;
  while ((index = text.indexOf('\n', index + 1)) != -1) {
    if (index != 0 && text[index - 1] == '\r') {
      windowsNewlines++;
    } else {
      unixNewlines++;
    }
  }
  return windowsNewlines > unixNewlines;
}
