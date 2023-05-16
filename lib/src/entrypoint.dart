// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:pool/pool.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:source_span/source_span.dart';
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
import 'package_config.dart' show PackageConfig;
import 'package_config.dart';
import 'package_graph.dart';
import 'package_name.dart';
import 'pub_embeddable_command.dart';
import 'pubspec.dart';
import 'sdk.dart';
import 'solver.dart';
import 'solver/report.dart';
import 'solver/solve_suggestions.dart';
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
  var sdkNames = sdks.keys.map((name) => '  $name').join('|');
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
  /// The directory where the package is stored.
  ///
  /// For global packages this is inside the pub cache.
  ///
  /// Except for packages globally activated from path.
  final String rootDir;

  Package? _root;

  /// The root package this entrypoint is associated with.
  ///
  /// For a global package, this is the activated package.
  Package get root => _root ??= Package.load(
        null,
        rootDir,
        cache.sources,
        withPubspecOverrides: true,
      );

  /// For a global package, this is the directory that the package is installed
  /// in. Non-global packages have null.
  final String? globalDir;

  /// The system-wide cache which caches packages that need to be fetched over
  /// the network.
  final SystemCache cache;

  /// Whether this entrypoint exists within the package cache.
  bool get isCached => p.isWithin(cache.rootDir, rootDir);

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
      try {
        return _lockFile = LockFile.load(lockFilePath, cache.sources);
      } on SourceSpanException catch (e) {
        throw SourceSpanApplicationException(
          e.message,
          e.span,
          explanation: 'Failed parsing lock file:',
          hint:
              'Consider deleting the file and running `$topLevelProgram pub get` to recreate it.',
        );
      }
    }
  }

  LockFile? _lockFile;

  /// The `.dart_tool/package_config.json` package-config of this entrypoint.
  ///
  /// Lazily initialized. Will throw [DataError] when initializing if the
  /// `.dart_tool/packageConfig.json` file doesn't exist or has a bad format .
  late PackageConfig packageConfig = () {
    late String packageConfigRaw;
    try {
      packageConfigRaw = readTextFile(packageConfigPath);
    } on FileException {
      dataError(
        'The "$packageConfigPath" file does not exist, please run "$topLevelProgram pub get".',
      );
    }
    late PackageConfig result;
    try {
      result = PackageConfig.fromJson(json.decode(packageConfigRaw) as Object);
    } on FormatException {
      badPackageConfig();
    }
    // Version 2 is the initial version number for `package_config.json`,
    // because `.packages` was version 1 (even if it was a different file).
    // If the version is different from 2, then it must be a newer incompatible
    // version, hence, the user should run `pub get` with the downgraded SDK.
    if (result.configVersion != 2) {
      badPackageConfig();
    }
    return result;
  }();

  /// The package graph for the application and all of its transitive
  /// dependencies.
  ///
  /// Throws a [DataError] if the `.dart_tool/package_config.json` file isn't
  /// up-to-date relative to the pubspec and the lockfile.
  PackageGraph get packageGraph => _packageGraph ??= _createPackageGraph();

  PackageGraph _createPackageGraph() {
    ensureUpToDate(); // TODO, really?
    var packages = {
      for (var packageEntry in packageConfig.nonInjectedPackages)
        packageEntry.name: Package.load(
          packageEntry.name,
          packageEntry.resolvedRootDir(packageConfigPath),
          cache.sources,
        ),
    };
    packages[root.name] = root;

    return PackageGraph(this, packages);
  }

  PackageGraph? _packageGraph;

  /// Where the lock file and package configurations are to be found.
  ///
  /// Global packages (except those from path source)
  /// store these in the global cache.
  String? get _configRoot => isCached ? globalDir : rootDir;

  /// The path to the entrypoint's ".packages" file.
  ///
  /// This file is being slowly deprecated in favor of
  /// `.dart_tool/package_config.json`. Pub will still create it, but will
  /// not require it or make use of it within pub.
  String get packagesFile => p.normalize(p.join(_configRoot!, '.packages'));

  /// The path to the entrypoint's ".dart_tool/package_config.json" file
  /// relative to the current working directory .
  late String packageConfigPath = p.relative(
    p.normalize(p.join(_configRoot!, '.dart_tool', 'package_config.json')),
  );

  /// The path to the entrypoint package's pubspec.
  String get pubspecPath => p.normalize(p.join(rootDir, 'pubspec.yaml'));

  /// The path to the entrypoint package's pubspec overrides file.
  String get pubspecOverridesPath =>
      p.normalize(p.join(rootDir, 'pubspec_overrides.yaml'));

  /// The path to the entrypoint package's lockfile.
  String get lockFilePath => p.normalize(p.join(_configRoot!, 'pubspec.lock'));

  /// The path to the entrypoint package's `.dart_tool/pub` cache directory.
  ///
  /// For globally activated packages from path, this is not the same as
  /// [configRoot], because the snapshots should be stored in the global cache,
  /// but the configuration is stored at the package itself.
  String get cachePath => globalDir ?? p.join(rootDir, '.dart_tool/pub');

  /// The path to the directory containing dependency executable snapshots.
  String get _snapshotPath => p.join(cachePath, 'bin');

  /// The path to the directory containing previous dill files for incremental
  /// builds.
  String get _incrementalDillsPath => p.join(cachePath, 'incremental');

  Entrypoint._(
    this.rootDir,
    this._lockFile,
    this._example,
    this._packageGraph,
    this.cache,
    this._root,
    this.globalDir,
  );

  /// An entrypoint representing a package at [rootDir].
  Entrypoint(
    this.rootDir,
    this.cache, {
    Pubspec? pubspec,
  })  : _root = pubspec == null ? null : Package.inMemory(pubspec),
        globalDir = null {
    if (p.isWithin(cache.rootDir, rootDir)) {
      fail('Cannot operate on packages inside the cache.');
    }
  }

  /// Creates an entrypoint at the same location, that will use [pubspec] for
  /// resolution.
  Entrypoint withPubspec(Pubspec pubspec) {
    return Entrypoint._(
      rootDir,
      _lockFile,
      _example,
      _packageGraph,
      cache,
      Package.inMemory(pubspec),
      globalDir,
    );
  }

  /// Creates an entrypoint given package and lockfile objects.
  /// If a SolveResult is already created it can be passed as an optimization.
  Entrypoint.global(
    this.globalDir,
    Package this._root,
    this._lockFile,
    this.cache, {
    SolveResult? solveResult,
  }) : rootDir = _root.dir {
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
  Future<void> writePackageConfigFile() async {
    final entrypointName = isGlobal ? null : root.name;
    ensureDir(p.dirname(packageConfigPath));
    writeTextFile(
      packageConfigPath,
      await lockFile.packageConfigFile(
        cache,
        entrypoint: entrypointName,
        entrypointSdkConstraint:
            root.pubspec.sdkConstraints[sdk.identifier]?.effectiveConstraint,
        relativeFrom: isGlobal ? null : rootDir,
      ),
    );
  }

  /// Gets all dependencies of the [root] package.
  ///
  /// Performs version resolution according to [SolveType].
  ///
  /// The iterable [unlock] specifies the list of packages whose versions can be
  /// changed even if they are locked in the pubspec.lock file.
  ///
  /// [analytics] holds the information needed for the embedded pub command to
  /// send analytics.
  ///
  /// Shows a report of the changes made relative to the previous lockfile. If
  /// this is an upgrade or downgrade, all transitive dependencies are shown in
  /// the report. Otherwise, only dependencies that were changed are shown. If
  /// [dryRun] is `true`, no physical changes are made.
  ///
  /// If [precompile] is `true` (the default), this snapshots dependencies'
  /// executables.
  ///
  /// if [summaryOnly] is `true` only success or failure will be
  /// shown --- in case of failure, a reproduction command is shown.
  ///
  /// Updates [lockFile] and [packageRoot] accordingly.
  ///
  /// If [enforceLockfile] is true no changes to the current lockfile are
  /// allowed. Instead the existing lockfile is loaded, verified against
  /// pubspec.yaml and all dependencies downloaded.
  Future<void> acquireDependencies(
    SolveType type, {
    Iterable<String>? unlock,
    bool dryRun = false,
    bool precompile = false,
    required PubAnalytics? analytics,
    bool summaryOnly = false,
    bool enforceLockfile = false,
  }) async {
    root; // This will throw early if pubspec.yaml could not be found.
    summaryOnly = summaryOnly || _summaryOnlyEnvironment;
    final suffix = rootDir == '.' ? '' : ' in $rootDir';

    if (enforceLockfile && !fileExists(lockFilePath)) {
      throw ApplicationException('''
Retrieving dependencies failed$suffix.
Cannot do `--enforce-lockfile` without an existing `pubspec.lock`.

Try running `$topLevelProgram pub get` to create `$lockFilePath`.''');
    }

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
    } on SolveFailure catch (e) {
      throw SolveFailure(
        e.incompatibility,
        suggestions: await suggestResolutionAlternatives(
          this,
          type,
          e.incompatibility,
          unlock ?? [],
          cache,
        ),
      );
    }

    // We have to download files also with --dry-run to ensure we know the
    // archive hashes for downloaded files.
    final newLockFile = await result.downloadCachedPackages(cache);

    final report = SolveReport(
      type,
      rootDir,
      root.pubspec,
      lockFile,
      newLockFile,
      result.availableVersions,
      cache,
      dryRun: dryRun,
      enforceLockfile: enforceLockfile,
      quiet: summaryOnly,
    );

    final hasChanges = await report.show();
    await report.summarize();
    if (enforceLockfile && hasChanges) {
      dataError('''
Unable to satisfy `$pubspecPath` using `$lockFilePath`$suffix.

To update `$lockFilePath` run `$topLevelProgram pub get`$suffix without
`--enforce-lockfile`.''');
    }

    if (!(dryRun || enforceLockfile)) {
      newLockFile.writeToFile(lockFilePath, cache);
    }

    _lockFile = newLockFile;

    if (!dryRun) {
      if (analytics != null) {
        result.sendAnalytics(analytics);
      }

      /// Build a package graph from the version solver results so we don't
      /// have to reload and reparse all the pubspecs.
      _packageGraph = PackageGraph.fromSolveResult(this, result);

      await writePackageConfigFile();

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
      return waitAndPrintErrors(
        executables.map((executable) async {
          await pool.withResource(() async {
            return _precompileExecutable(executable);
          });
        }),
      );
    });
  }

  /// Precompiles executable .dart file at [path] to a snapshot.
  ///
  /// The [additionalSources], if provided, instruct the compiler to include
  /// additional source files into compilation even if they are not referenced
  /// from the main library.
  ///
  /// The [nativeAssets], if provided, instruct the compiler include a native
  /// assets map.
  Future<void> precompileExecutable(
    Executable executable, {
    List<String> additionalSources = const [],
    String? nativeAssets,
  }) async {
    await log.progress('Building package executable', () async {
      ensureDir(p.dirname(pathOfExecutable(executable)));
      return waitAndPrintErrors([
        _precompileExecutable(
          executable,
          additionalSources: additionalSources,
          nativeAssets: nativeAssets,
        )
      ]);
    });
  }

  Future<void> _precompileExecutable(
    Executable executable, {
    List<String> additionalSources = const [],
    String? nativeAssets,
  }) async {
    final package = executable.package;

    await dart.precompile(
      executablePath: resolveExecutable(executable),
      outputPath: pathOfExecutable(executable),
      incrementalDillPath: incrementalDillPathOfExecutable(executable),
      packageConfigPath: packageConfigPath,
      name: '$package:${p.basenameWithoutExtension(executable.relativePath)}',
      additionalSources: additionalSources,
      nativeAssets: nativeAssets,
    );
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
        ? p.join(
            _snapshotPath,
            '${p.basename(executable.relativePath)}-$versionSuffix.snapshot',
          )
        : p.join(
            _snapshotPath,
            executable.package,
            '${p.basename(executable.relativePath)}-$versionSuffix.snapshot',
          );
  }

  String incrementalDillPathOfExecutable(Executable executable) {
    assert(p.isRelative(executable.relativePath));
    return isGlobal
        ? p.join(
            _incrementalDillsPath,
            '${p.basename(executable.relativePath)}.incremental.dill',
          )
        : p.join(
            _incrementalDillsPath,
            executable.package,
            '${p.basename(executable.relativePath)}.incremental.dill',
          );
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

  /// Does a fast-pass check to see if the resolution is up-to-date
  /// ([_isUpToDate]). If not, run a resolution with `pub get` semantics.
  ///
  /// If [checkForSdkUpdate] is `true`, the resolution is considered outdated if
  /// the package_config.json was created by a different sdk. See
  /// [_isPackageConfigGeneratedBySameDartSdk].
  ///
  /// If [summaryOnly] is `true` (the default) only a short summary is shown of
  /// the solve.
  ///
  /// If [onlyOutputWhenTerminal] is `true` (the default) there will be no
  /// output if no terminal is attached.
  Future<void> ensureUpToDate({
    bool checkForSdkUpdate = false,
    PubAnalytics? analytics,
    bool summaryOnly = true,
    bool onlyOutputWhenTerminal = true,
  }) async {
    if (!_isUpToDate(checkForSdkUpdate: checkForSdkUpdate)) {
      if (onlyOutputWhenTerminal) {
        await log.errorsOnlyUnlessTerminal(() async {
          await acquireDependencies(
            SolveType.get,
            analytics: analytics,
            summaryOnly: summaryOnly,
          );
        });
      } else {
        await acquireDependencies(
          SolveType.get,
          analytics: analytics,
          summaryOnly: summaryOnly,
        );
      }
    } else {
      log.fine('Package Config up to date.');
    }
  }

  /// Whether `.dart_tool/package_config.json` file exists and if it's
  /// up-to-date relative to the lockfile and the pubspec.
  ///
  /// A `.packages` file is not required. But if it exists it is checked for
  /// consistency with the pubspec.lock.
  bool _isUpToDate({bool checkForSdkUpdate = false}) {
    if (isCached) return true;
    final pubspecStat = tryStatFile(pubspecPath);
    if (pubspecStat == null) {
      log.fine(
        'Could not find a file named "pubspec.yaml" in '
        '"${canonicalize(rootDir)}".',
      );
      return false;
    }
    final lockFileStat = tryStatFile(lockFilePath);
    if (lockFileStat == null) {
      log.fine('No $lockFilePath file found.');
      return false;
    }
    final packageConfigStat = tryStatFile(packageConfigPath);
    if (packageConfigStat == null) {
      log.fine('No $packageConfigPath file found".\n');
      return false;
    }

    // Manually parse the lockfile because a full YAML parse is relatively slow
    // and this is on the hot path for "pub run".
    var lockFileText = readTextFile(lockFilePath);
    var hasPathDependencies = lockFileText.contains('\n    source: path\n');

    var lockFileModified = lockFileStat.modified;

    var pubspecChanged = lockFileModified.isBefore(pubspecStat.modified);
    var pubspecOverridesChanged = false;

    final pubspecOverridesStat = tryStatFile(pubspecOverridesPath);
    if (pubspecOverridesStat != null) {
      pubspecOverridesChanged =
          lockFileModified.isBefore(pubspecOverridesStat.modified);
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
      if (!_isLockFileUpToDate()) {
        return false;
      }
      if (_arePackagesAvailable()) {
        touchedLockFile = true;
        touch(lockFilePath);
      } else {
        var filePath = pubspecChanged ? pubspecPath : pubspecOverridesPath;
        log.fine('The $filePath file has changed since the $lockFilePath '
            'file was generated, please run "$topLevelProgram pub get" again.');
        return false;
      }
    }

    if (packageConfigStat.modified.isBefore(lockFileModified) ||
        hasPathDependencies) {
      // If `package_config.json` is older than `pubspec.lock` or we have
      // path dependencies, then we check that `package_config.json` is a
      // correct configuration on the local machine. This aims to:
      //  * Mitigate issues when copying a folder from one machine to another.
      //  * Force `pub get` if a path dependency has changed language version.
      if (!_isPackageConfigUpToDate()) return false;
      touch(packageConfigPath);
    } else {
      if (touchedLockFile) {
        touch(packageConfigPath);
      }
    }

    for (final match in _sdkConstraint.allMatches(lockFileText)) {
      final identifier = match[1] == 'sdk' ? 'dart' : match[1]!.trim();
      final sdk = sdks[identifier]!;
      // Don't complain if there's an SDK constraint for an unavailable SDK. For
      // example, the Flutter SDK being unavailable just means that we aren't
      // running from within the `flutter` executable, and we want users to be
      // able to `pub run` non-Flutter tools even in a Flutter app.
      if (!sdk.isAvailable) continue;

      final parsedConstraint = VersionConstraint.parse(match[2]!);
      if (!parsedConstraint.allows(sdk.version!)) {
        log.fine('${sdk.name} ${sdk.version} is incompatible with your '
            "dependencies' SDK constraints.");
        return false;
      }
    }
    // We want to do ensure a pub get gets run when updating a minor version of
    // the Dart SDK.
    //
    // Putting this check last because it leads to less specific messages than
    // the 'incompatible sdk' check above.
    if (checkForSdkUpdate && !_isPackageConfigGeneratedBySameDartSdk()) {
      return false;
    }
    return true;
  }

  /// Whether the lockfile is out of date with respect to the
  /// pubspec.
  ///
  /// If any mutable pubspec contains dependencies that are not in the lockfile
  /// or that don't match what's in there, this will return `false`.
  bool _isLockFileUpToDate() {
    if (!root.immediateDependencies.values.every(_isDependencyUpToDate)) {
      log.fine('The $pubspecPath file has changed since the $lockFilePath file '
          'was generated.');
      return false;
    }

    var overrides = MapKeySet(root.dependencyOverrides);

    // Check that uncached dependencies' pubspecs are also still satisfied,
    // since they're mutable and may have changed since the last get.
    for (var id in lockFile.packages.values) {
      final source = id.source;
      if (source is CachedSource) continue;

      try {
        if (cache.load(id).dependencies.values.every(
              (dep) =>
                  overrides.contains(dep.name) || _isDependencyUpToDate(dep),
            )) {
          continue;
        }
      } on FileException {
        // If we can't load the pubspec, the user needs to re-run "pub get".
      }

      final relativePubspecPath =
          p.join(cache.getDirectory(id, relativeFrom: '.'), 'pubspec.yaml');
      log.fine('$relativePubspecPath has '
          'changed since the $lockFilePath file was generated.');
      return false;
    }
    return true;
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
        cache.getDirectory(lockFileId, relativeFrom: rootDir),
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

  /// Whether or not the `.dart_tool/package_config.json` file is
  /// out of date with respect to the lockfile.
  bool _isPackageConfigUpToDate() {
    final packagePathsMapping = <String, String>{};

    final packagesToCheck = packageConfig.nonInjectedPackages;
    for (final pkg in packagesToCheck) {
      // Pub always makes a packageUri of lib/
      if (pkg.packageUri == null || pkg.packageUri.toString() != 'lib/') {
        log.fine(
          'The "$packageConfigPath" file is not recognized by this pub version.',
        );
        return false;
      }
      packagePathsMapping[pkg.name] =
          root.path('.dart_tool', p.fromUri(pkg.rootUri));
    }
    if (!_isPackagePathsMappingUpToDateWithLockfile(packagePathsMapping)) {
      log.fine('The $lockFilePath file has changed since the '
          '$packageConfigPath file '
          'was generated, please run "$topLevelProgram pub get" again.');
      return false;
    }

    // Check if language version specified in the `package_config.json` is
    // correct. This is important for path dependencies as these can mutate.
    for (final pkg in packageConfig.nonInjectedPackages) {
      if (pkg.name == root.name) continue;
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
        final languageVersion = cache.load(id).pubspec.languageVersion;
        if (pkg.languageVersion != languageVersion) {
          final relativePubspecPath = p.join(
            cache.getDirectory(id, relativeFrom: '.'),
            'pubspec.yaml',
          );
          log.fine('$relativePubspecPath has '
              'changed since the $lockFilePath file was generated.');
          return false;
        }
      } on FileException {
        log.fine('Failed to read pubspec.yaml for "${pkg.name}", perhaps the '
            'entry is missing.');
        return false;
      }
    }
    return true;
  }

  /// Whether or not the `.dart_tool/package_config.json` file is was
  /// generated by a different sdk down to changes in minor versions.
  bool _isPackageConfigGeneratedBySameDartSdk() {
    final generatorVersion = packageConfig.generatorVersion;
    if (generatorVersion == null ||
        generatorVersion.major != sdk.version.major ||
        generatorVersion.minor != sdk.version.minor) {
      log.fine('The sdk was updated since last package resolution.');
      return false;
    }
    return true;
  }

  /// We require an SDK constraint lower-bound as of Dart 2.12.0
  ///
  /// We don't allow unknown sdks.
  void _checkSdkConstraint(Pubspec pubspec) {
    final dartSdkConstraint = pubspec.dartSdkConstraint.effectiveConstraint;
    // Suggest an sdk constraint giving the same language version as the
    // current sdk.
    var suggestedConstraint = VersionConstraint.compatibleWith(
      Version(sdk.version.major, sdk.version.minor, 0),
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
    if (dartSdkConstraint is! VersionRange || dartSdkConstraint.min == null) {
      throw DataException('''
$pubspecPath has no lower-bound SDK constraint.
You should edit $pubspecPath to contain an SDK constraint:

environment:
  sdk: '${suggestedConstraint.asCompatibleWithIfPossible()}'

See https://dart.dev/go/sdk-constraint
''');
    }
    if (!LanguageVersion.fromSdkConstraint(dartSdkConstraint)
        .supportsNullSafety) {
      throw DataException('''
The lower bound of "sdk: '$dartSdkConstraint'" must be 2.12.0'
or higher to enable null safety.

The current Dart SDK (${sdk.version}) only supports null safety.

For details, see https://dart.dev/null-safety
''');
    }
    for (final sdk in pubspec.sdkConstraints.keys) {
      if (!sdks.containsKey(sdk)) {
        final environment = pubspec.fields.nodes['environment'] as YamlMap;
        final keyNode = environment.nodes.entries
            .firstWhere((e) => (e.key as YamlNode).value == sdk)
            .key as YamlNode;
        throw SourceSpanApplicationException(
          '''
$pubspecPath refers to an unknown sdk '$sdk'.

Did you mean to add it as a dependency?

Either remove the constraint, or upgrade to a version of pub that supports the
given sdk.

See https://dart.dev/go/sdk-constraint
''',
          keyNode.span,
        );
      }
    }
  }

  Never badPackageConfig() {
    dataError('The "$packageConfigPath" file is not recognized by '
        '"pub" version, please run "$topLevelProgram pub get".');
  }

  /// Setting the `PUB_SUMMARY_ONLY` environment variable to anything but '0'
  /// will result in [acquireDependencies] to only print a summary of the
  /// results.
  bool get _summaryOnlyEnvironment =>
      (Platform.environment['PUB_SUMMARY_ONLY'] ?? '0') != '0';
}
