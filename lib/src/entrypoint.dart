// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:pool/pool.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:source_span/source_span.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

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
import 'package_graph.dart';
import 'package_name.dart';
import 'pubspec.dart';
import 'pubspec_utils.dart';
import 'sdk.dart';
import 'sdk/flutter.dart';
import 'solver.dart';
import 'solver/report.dart';
import 'solver/solve_suggestions.dart';
import 'source/cached.dart';
import 'source/hosted.dart';
import 'source/root.dart';
import 'source/unknown.dart';
import 'system_cache.dart';
import 'utils.dart';

/// The context surrounding the workspace pub is operating on.
///
/// Pub operates over a directed graph of dependencies that starts at a root
/// "entrypoint" package. This is typically the package where the current
/// working directory is located.
///
/// An entrypoint knows the [workspaceRoot] package it is associated with and is
/// responsible for managing the package config (.dart_tool/package_config.json)
/// and lock file (pubspec.lock) for it.
///
/// While entrypoints are typically applications, a pure library package may end
/// up being used as an entrypoint while under development. Also, a single
/// package may be used as an entrypoint in one context but not in another. For
/// example, a package that contains a reusable library may not be the
/// entrypoint when used by an app, but may be the entrypoint when you're
/// running its tests.
class Entrypoint {
  /// The directory where this entrypoint is created.
  ///
  /// [workspaceRoot] will be the package in the nearest parent directory that
  /// has `resolution: null`
  final String workingDir;

  /// Finds the [workspaceRoot] and [workPackage] based on [workingDir].
  ///
  /// Works by iterating through the parent directories from [workingDir].
  ///
  /// [workPackage] is the package of first dir we find with a `pubspec.yaml`
  /// file.
  ///
  /// [workspaceRoot] is the package of the first dir we find with a
  /// `pubspec.yaml` that does not have `resolution: workspace`.
  ///
  /// [workPackage] and [workspaceRoot] can be the same. And will always be the
  /// same when no `workspace` is involved.
  /// =
  /// If [workingDir] doesn't exist, [fail].
  ///
  /// If no `pubspec.yaml` is found without `resolution: workspace` we [fail].
  static ({Package root, Package work}) _loadWorkspace(
    String workingDir,
    SystemCache cache,
  ) {
    if (!dirExists(workingDir)) {
      fail('The directory `$workingDir` does not exist.');
    }
    // Keep track of all the pubspecs met when walking up the file system.
    // The first of these is the workingPackage.
    final pubspecsMet = <String, Pubspec>{};
    for (final dir in parentDirs(workingDir)) {
      final Pubspec pubspec;

      try {
        pubspec = Pubspec.load(
          dir,
          cache.sources,
          containingDescription: RootDescription(dir),
          allowOverridesFile: true,
        );
      } on FileException {
        continue;
      }
      pubspecsMet[p.canonicalize(dir)] = pubspec;
      final Package root;
      if (pubspec.resolution == Resolution.none) {
        root = Package.load(
          dir,
          loadPubspec: (
            path, {
            expectedName,
            required withPubspecOverrides,
          }) =>
              pubspecsMet[p.canonicalize(path)] ??
              Pubspec.load(
                path,
                cache.sources,
                expectedName: expectedName,
                allowOverridesFile: withPubspecOverrides,
                containingDescription: RootDescription(path),
              ),
          withPubspecOverrides: true,
        );
        for (final package in root.transitiveWorkspace) {
          if (identical(pubspecsMet.entries.first.value, package.pubspec)) {
            validateWorkspace(root);
            return (root: root, work: package);
          }
        }
        assert(false);
      }
    }
    if (pubspecsMet.isEmpty) {
      throw FileException(
        'Found no `pubspec.yaml` file in `${p.normalize(p.absolute(workingDir))}` or parent directories',
        p.join(workingDir, 'pubspec.yaml'),
      );
    } else {
      final firstEntry = pubspecsMet.entries.first;
      throw FileException(
        '''
Found a pubspec.yaml at ${firstEntry.key}. But it has resolution `${firstEntry.value.resolution.name}`.
But found no workspace root including it in parent directories.

See $workspacesDocUrl for more information.''',
        p.join(workingDir, 'pubspec.yaml'),
      );
    }
  }

  /// Stores the result of [_loadWorkspace].
  /// Only access via [workspaceRoot], [workPackage] and [canFindWorkspaceRoot].
  ({Package root, Package work})? _packages;

  /// Only access via [workspaceRoot], [workPackage] and [canFindWorkspaceRoot].
  ({Package root, Package work}) get _getPackages =>
      _packages ??= _loadWorkspace(workingDir, cache);

  /// The root package this entrypoint is associated with.
  ///
  /// For a global package, this is the activated package.
  Package get workspaceRoot => _getPackages.root;

  /// True if we can find a `pubspec.yaml` to resolve in [workingDir] or any
  /// parent directory.
  bool get canFindWorkspaceRoot {
    try {
      _getPackages;
      return true;
    } on FileException {
      return false;
    }
  }

  /// The "focus" package that the current command should act upon.
  ///
  /// It will be the package in the nearest parent directory to `workingDir`.
  /// Example: if a workspace looks like this:
  ///
  /// foo/ pubspec.yaml # contains `workspace: [- 'bar'] bar/ pubspec.yaml #
  ///   contains `resolution: workspace`.
  ///
  /// Running `pub add` in `foo/bar` will have bar as workPackage, and add
  /// dependencies to `foo/bar/pubspec.yaml`.
  ///
  /// Running `pub add` in `foo` will have foo as workPackage, and add
  /// dependencies to `foo/pubspec.yaml`.
  Package get workPackage => _getPackages.work;

  /// The system-wide cache which caches packages that need to be fetched over
  /// the network.
  final SystemCache cache;

  /// Whether this entrypoint exists within the package cache.
  bool get isCached => p.isWithin(cache.rootDir, workingDir);

  /// Whether this is an entrypoint for a globally-activated package.
  ///
  /// False for path-activated global packages.
  final bool isCachedGlobal;

  /// The lockfile for the entrypoint.
  ///
  /// If not provided to the entrypoint, it will be loaded lazily from disk.
  LockFile get lockFile => _lockFile ??= _loadLockFile(lockFilePath, cache);

  static LockFile _loadLockFile(String lockFilePath, SystemCache cache) {
    if (!fileExists(lockFilePath)) {
      return LockFile.empty();
    } else {
      try {
        return LockFile.load(lockFilePath, cache.sources);
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
  PackageConfig get packageConfig =>
      _packageConfig ??= _loadPackageConfig(packageConfigPath);
  PackageConfig? _packageConfig;

  static PackageConfig _loadPackageConfig(String packageConfigPath) {
    Never badPackageConfig() {
      dataError('The "$packageConfigPath" file is not recognized by '
          '"pub" version, please run "$topLevelProgram pub get".');
    }

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
      result = PackageConfig.fromJson(
        json.decode(packageConfigRaw) as Object?,
      );
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
  }

  /// The package graph for the application and all of its transitive
  /// dependencies.
  ///
  /// Throws a [DataError] if the `.dart_tool/package_config.json` file isn't
  /// up-to-date relative to the pubspec and the lockfile.
  Future<PackageGraph> get packageGraph =>
      _packageGraph ??= _createPackageGraph();

  Future<PackageGraph> _createPackageGraph() async {
    // TODO(sigurdm): consider having [ensureUptoDate] and [acquireDependencies]
    // return the package-graph, such it by construction will always made from an
    // up-to-date package-config.
    await ensureUpToDate(workspaceRoot.dir, cache: cache);
    final packages = {
      for (var packageEntry in packageConfig.nonInjectedPackages)
        packageEntry.name: Package.load(
          packageEntry.resolvedRootDir(packageConfigPath),
          expectedName: packageEntry.name,
          loadPubspec: Pubspec.loadRootWithSources(cache.sources),
        ),
    };
    packages[workspaceRoot.name] = workspaceRoot;

    return PackageGraph(this, packages);
  }

  Future<PackageGraph>? _packageGraph;

  /// The path to the entrypoint's ".dart_tool/package_config.json" file
  /// relative to the current working directory .
  late String packageConfigPath = p.relative(
    p.normalize(p.join(workspaceRoot.dir, '.dart_tool', 'package_config.json')),
  );

  /// The path to the entrypoint workspace's lockfile.
  String get lockFilePath =>
      p.normalize(p.join(workspaceRoot.dir, 'pubspec.lock'));

  /// The path to the directory containing dependency executable snapshots.
  String get _snapshotPath => p.join(
        isCachedGlobal
            ? workspaceRoot.dir
            : p.join(workspaceRoot.dir, '.dart_tool/pub'),
        'bin',
      );

  Entrypoint._(
    this.workingDir,
    this._lockFile,
    this._example,
    this._packageGraph,
    this.cache,
    this._packages,
    this.isCachedGlobal,
  );

  /// An entrypoint for the workspace containing [workingDir]/
  ///
  /// If [checkInCache] is `true` (the default) an error will be thrown if
  /// [rootDir] is located inside [cache.rootDir].

  Entrypoint(
    this.workingDir,
    this.cache, {
    bool checkInCache = true,
  }) : isCachedGlobal = false {
    if (checkInCache && p.isWithin(cache.rootDir, workingDir)) {
      fail('Cannot operate on packages inside the cache.');
    }
  }

  /// Creates an entrypoint at the same location, but with each pubspec in
  /// [updatedPubspecs] replacing the with one for the corresponding package.
  Entrypoint withUpdatedRootPubspecs(Map<Package, Pubspec> updatedPubspecs) {
    final newWorkspaceRoot = workspaceRoot.transformWorkspace(
      (package) => updatedPubspecs[package] ?? package.pubspec,
    );
    final newWorkPackage = newWorkspaceRoot.transitiveWorkspace
        .firstWhere((package) => package.dir == workPackage.dir);
    return Entrypoint._(
      workingDir,
      _lockFile,
      _example,
      _packageGraph,
      cache,
      (root: newWorkspaceRoot, work: newWorkPackage),
      isCachedGlobal,
    );
  }

  /// Creates an entrypoint at the same location, that will use [pubspec] for
  /// resolution of the [workPackage].
  Entrypoint withWorkPubspec(Pubspec pubspec) {
    return withUpdatedRootPubspecs({workPackage: pubspec});
  }

  /// Creates an entrypoint given package and lockfile objects.
  /// If a SolveResult is already created it can be passed as an optimization.
  Entrypoint.global(
    Package package,
    this._lockFile,
    this.cache, {
    SolveResult? solveResult,
  })  : _packages = (root: package, work: package),
        workingDir = package.dir,
        isCachedGlobal = true {
    if (solveResult != null) {
      _packageGraph =
          Future.value(PackageGraph.fromSolveResult(this, solveResult));
    }
  }

  /// Gets the [Entrypoint] package for the current working directory.
  ///
  /// This will be null if the example folder doesn't have a `pubspec.yaml`.
  Entrypoint? get example {
    if (_example != null) return _example;
    if (!fileExists(workspaceRoot.path('example', 'pubspec.yaml'))) {
      return null;
    }
    return _example = Entrypoint(workspaceRoot.path('example'), cache);
  }

  Entrypoint? _example;

  /// Writes the .dart_tool/package_config.json file and workspace references to
  /// it.
  ///
  /// If the workspace is non-trivial: For each package in the workspace write:
  /// `.dart_tool/pub/workspace_ref.json` with a pointer to the workspace root
  /// package dir.
  Future<void> writePackageConfigFile() async {
    ensureDir(p.dirname(packageConfigPath));
    writeTextFile(
      packageConfigPath,
      await _packageConfigFile(
        cache,
        entrypointSdkConstraint: workspaceRoot
            .pubspec.sdkConstraints[sdk.identifier]?.effectiveConstraint,
      ),
    );
    if (workspaceRoot.workspaceChildren.isNotEmpty) {
      for (final package in workspaceRoot.transitiveWorkspace) {
        final workspaceRefDir = p.join(package.dir, '.dart_tool', 'pub');
        final workspaceRefPath = p.join(workspaceRefDir, 'workspace_ref.json');
        ensureDir(workspaceRefDir);
        final relativeRootPath =
            p.relative(workspaceRoot.dir, from: workspaceRefDir);
        writeTextFile(
          workspaceRefPath,
          '${JsonEncoder.withIndent('  ').convert({
                'workspaceRoot': relativeRootPath,
              })}\n',
        );
      }
    }
  }

  /// Returns the contents of the `.dart_tool/package_config` file generated
  /// from this entrypoint based on [lockFile].
  ///
  /// If [isCachedGlobal] no entry will be created for [workspaceRoot].
  Future<String> _packageConfigFile(
    SystemCache cache, {
    VersionConstraint? entrypointSdkConstraint,
  }) async {
    final entries = <PackageConfigEntry>[];
    late final relativeFromPath = p.join(workspaceRoot.dir, '.dart_tool');
    for (final name in ordered(lockFile.packages.keys)) {
      final id = lockFile.packages[name]!;
      final rootPath = cache.getDirectory(id, relativeFrom: relativeFromPath);
      final pubspec = await cache.describe(id);
      entries.add(
        PackageConfigEntry(
          name: name,
          rootUri: p.toUri(rootPath),
          packageUri: p.toUri('lib/'),
          languageVersion: pubspec.languageVersion,
        ),
      );
    }

    if (!isCachedGlobal) {
      /// Run through the entire workspace transitive closure and add an entry
      /// for each package.
      for (final package in workspaceRoot.transitiveWorkspace) {
        entries.add(
          PackageConfigEntry(
            name: package.name,
            rootUri: p.toUri(
              p.relative(
                package.dir,
                from: p.join(workspaceRoot.dir, '.dart_tool'),
              ),
            ),
            packageUri: p.toUri('lib/'),
            languageVersion: package.pubspec.languageVersion,
          ),
        );
      }
    }

    final packageConfig = PackageConfig(
      configVersion: 2,
      packages: entries,
      generated: DateTime.now(),
      generator: 'pub',
      generatorVersion: sdk.version,
      additionalProperties: {
        if (FlutterSdk().isAvailable) ...{
          'flutterRoot':
              p.toUri(p.absolute(FlutterSdk().rootDirectory!)).toString(),
          'flutterVersion': FlutterSdk().version.toString(),
        },
        'pubCache': p.toUri(p.absolute(cache.rootDir)).toString(),
      },
    );

    return '${JsonEncoder.withIndent('  ').convert(packageConfig.toJson())}\n';
  }

  /// Gets all dependencies of the [workspaceRoot] package.
  ///
  /// Performs version resolution according to [SolveType].
  ///
  /// The iterable [unlock] specifies the list of packages whose versions can be
  /// changed even if they are locked in the pubspec.lock file.
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
    bool summaryOnly = false,
    bool enforceLockfile = false,
  }) async {
    workspaceRoot; // This will throw early if pubspec.yaml could not be found.
    summaryOnly = summaryOnly || _summaryOnlyEnvironment;
    final suffix = workspaceRoot.dir == '.'
        ? ''
        : ' in `${workspaceRoot.presentationDir}`';

    if (enforceLockfile && !fileExists(lockFilePath)) {
      throw ApplicationException('''
Retrieving dependencies failed$suffix.
Cannot do `--enforce-lockfile` without an existing `pubspec.lock`.

Try running `$topLevelProgram pub get` to create `$lockFilePath`.''');
    }

    SolveResult result;

    try {
      result = await log.progress('Resolving dependencies$suffix', () async {
        // TODO(https://github.com/dart-lang/pub/issues/4127): Check this for
        // all workspace pubspecs.
        _checkSdkConstraint(workspaceRoot.pubspecPath, workspaceRoot.pubspec);
        return resolveVersions(
          type,
          cache,
          workspaceRoot,
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
      workspaceRoot.dir,
      workspaceRoot.pubspec,
      workspaceRoot.allOverridesInWorkspace,
      lockFile,
      newLockFile,
      result.availableVersions,
      cache,
      dryRun: dryRun,
      enforceLockfile: enforceLockfile,
      quiet: summaryOnly,
    );

    await report.show(summary: true);
    if (enforceLockfile && !_lockfilesMatch(lockFile, newLockFile)) {
      dataError('''
Unable to satisfy `${workspaceRoot.pubspecPath}` using `$lockFilePath`$suffix.

To update `$lockFilePath` run `$topLevelProgram pub get`$suffix without
`--enforce-lockfile`.''');
    }

    if (!(dryRun || enforceLockfile)) {
      newLockFile.writeToFile(lockFilePath, cache);
    }

    _lockFile = newLockFile;

    if (!dryRun) {
      _removeStrayLockAndConfigFiles();

      /// Build a package graph from the version solver results so we don't
      /// have to reload and reparse all the pubspecs.
      _packageGraph = Future.value(PackageGraph.fromSolveResult(this, result));

      await writePackageConfigFile();

      try {
        if (precompile) {
          await precompileExecutables();
        } else {
          await _deleteExecutableSnapshots();
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
  Future<List<Executable>> get _builtExecutables async {
    final graph = await packageGraph;
    final r = workspaceRoot.immediateDependencies.keys.expand((packageName) {
      final package = graph.packages[packageName]!;
      return package.executablePaths
          .map((path) => Executable(packageName, path));
    }).toList();
    return r;
  }

  /// Precompiles all [_builtExecutables].
  Future<void> precompileExecutables() async {
    final executables = await _builtExecutables;

    if (executables.isEmpty) return;

    await log.progress('Building package executables', () async {
      if (isCachedGlobal) {
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
      ensureDir(p.dirname(pathOfSnapshot(executable)));
      return waitAndPrintErrors([
        _precompileExecutable(
          executable,
          additionalSources: additionalSources,
          nativeAssets: nativeAssets,
        ),
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
      executablePath: executable.resolve(packageConfig, packageConfigPath),
      outputPath: pathOfSnapshot(executable),
      packageConfigPath: packageConfigPath,
      name: '$package:${p.basenameWithoutExtension(executable.relativePath)}',
      additionalSources: additionalSources,
      nativeAssets: nativeAssets,
    );
    cache.maintainCache();
  }

  /// The location of the snapshot of the dart program at [path] in [package]
  /// will be stored here.
  ///
  /// We use the sdk version to make sure we don't run snapshots from a
  /// different sdk.
  ///
  /// [path] must be relative.
  String pathOfSnapshot(Executable executable) {
    return isCachedGlobal
        ? executable.pathOfGlobalSnapshot(workspaceRoot.dir)
        : executable.pathOfSnapshot(workspaceRoot.dir);
  }

  /// Deletes cached snapshots that are from a different sdk.
  Future<void> _deleteExecutableSnapshots() async {
    if (!dirExists(_snapshotPath)) return;
    // Clean out any outdated snapshots.
    for (var entry in listDir(_snapshotPath)) {
      if (!fileExists(entry)) {
        // Not a file
        continue;
      }

      if (!entry.endsWith('${sdk.version}.snapshot')) {
        // Made with a different sdk version. Clean it up.
        deleteEntry(entry);
      }
    }
  }

  /// Does a fast-pass check to see if the resolution is up-to-date
  /// ([_isUpToDate]). If not, run a resolution with `pub get` semantics.
  ///
  /// If [summaryOnly] is `true` (the default) only a short summary is shown of
  /// the solve.
  ///
  /// If [onlyOutputWhenTerminal] is `true` (the default) there will be no
  /// output if no terminal is attached.
  static Future<PackageConfig> ensureUpToDate(
    String dir, {
    required SystemCache cache,
    bool summaryOnly = true,
    bool onlyOutputWhenTerminal = true,
  }) async {
    final lockFilePath = p.normalize(p.join(dir, 'pubspec.lock'));
    final packageConfigPath =
        p.normalize(p.join(dir, '.dart_tool', 'package_config.json'));

    /// Whether the lockfile is out of date with respect to the dependencies'
    /// pubspecs.
    ///
    /// If any mutable pubspec contains dependencies that are not in the lockfile
    /// or that don't match what's in there, this will return `false`.
    bool isLockFileUpToDate(LockFile lockFile, Package root) {
      /// Returns whether the locked version of [dep] matches the dependency.
      bool isDependencyUpToDate(PackageRange dep) {
        if (dep.name == root.name) return true;

        final locked = lockFile.packages[dep.name];
        return locked != null && dep.allows(locked);
      }

      for (final MapEntry(key: sdkName, value: constraint)
          in lockFile.sdkConstraints.entries) {
        final sdk = sdks[sdkName];
        if (sdk == null) {
          log.fine('Unknown sdk $sdkName in `$lockFilePath`');
          return false;
        }
        if (!sdk.isAvailable) {
          log.fine('sdk: ${sdk.name} not available');
          return false;
        }
        final sdkVersion = sdk.version;
        if (sdkVersion != null) {
          if (!constraint.effectiveConstraint.allows(sdkVersion)) {
            log.fine(
              '`$lockFilePath` requires $sdkName $constraint. Current version is $sdkVersion',
            );
            return false;
          }
        }
      }

      if (!root.immediateDependencies.values.every(isDependencyUpToDate)) {
        final pubspecPath = p.normalize(p.join(dir, 'pubspec.yaml'));

        log.fine(
            'The $pubspecPath file has changed since the $lockFilePath file '
            'was generated.');
        return false;
      }

      // Check that uncached dependencies' pubspecs are also still satisfied,
      // since they're mutable and may have changed since the last get.
      for (var id in lockFile.packages.values) {
        final source = id.source;
        if (source is CachedSource) continue;

        try {
          if (cache.load(id).dependencies.values.every(
                (dep) =>
                    root.allOverridesInWorkspace.containsKey(dep.name) ||
                    isDependencyUpToDate(dep),
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

    /// Whether or not the `.dart_tool/package_config.json` file is
    /// out of date with respect to the lockfile.
    bool isPackageConfigUpToDate(
      PackageConfig packageConfig,
      LockFile lockFile,
      Package root,
    ) {
      /// Determines if [lockFile] agrees with the given [packagePathsMapping].
      ///
      /// The [packagePathsMapping] is a mapping from package names to paths where
      /// the packages are located. (The library is located under
      /// `lib/` relative to the path given).
      bool isPackagePathsMappingUpToDateWithLockfile(
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
          log.fine(packagePathsMapping.toString());
          log.fine(lockFile.packages.toString());
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
      if (!isPackagePathsMappingUpToDateWithLockfile(packagePathsMapping)) {
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

    /// The [PackageConfig] object representing `.dart_tool/package_config.json`
    /// if it and `pubspec.lock` exist and are up to date with respect to
    /// pubspec.yaml and its dependencies. Or `null` if it is outdate
    ///
    /// Always returns `null` if `.dart_tool/package_config.json` was generated
    /// with a different PUB_CACHE location, a different $FLUTTER_ROOT or a
    /// different Dart or Flutter SDK version.
    ///
    /// Otherwise first the `modified` timestamps are compared, and if
    /// `.dart_tool/package_config.json` is newer than `pubspec.lock` that is
    /// newer than all pubspec.yamls of all packages in
    /// `.dart_tool/package_config.json` we short-circuit and return true.
    ///
    /// If any of the timestamps are out of order, the resolution in
    /// pubspec.lock is validated against constraints of all pubspec.yamls, and
    /// the packages of `.dart_tool/package_config.json` is validated against
    /// pubspec.lock. We do this extra round of checking to accomodate for cases
    /// where version control or other processes mess up the timestamp order.
    ///
    /// If the resolution is still valid, the timestamps are updated and this
    /// returns `true`. Otherwise this returns `false`.
    ///
    /// This check is on the fast-path of `dart run` and should do as little
    /// work as possible. Specifically we avoid parsing any yaml when the
    /// timestamps are in the right order.
    ///
    /// `.dart_tool/package_config.json` is read parsed. In the case of `dart
    /// run` this is acceptable: we speculate that it brings it to the file
    /// system cache and the dart VM is going to read the file anyways.
    ///
    /// Note this procedure will give false positives if the timestamps are
    /// artificially brought in the "right" order. (eg. by manually running
    /// `touch pubspec.lock; touch .dart_tool/package_config.json`) - that is
    /// hard to avoid, but also unlikely to happen by accident because
    /// `.dart_tool/package_config.json` is not checked into version control.
    PackageConfig? isResolutionUpToDate() {
      late final packageConfig = _loadPackageConfig(packageConfigPath);
      if (p.isWithin(cache.rootDir, packageConfigPath)) {
        // We always consider a global package (inside the cache) up-to-date.
        return packageConfig;
      }

      /// Whether or not the `.dart_tool/package_config.json` file is was
      /// generated by a different sdk down to changes in minor versions.
      bool isPackageConfigGeneratedBySameDartSdk() {
        final generatorVersion = packageConfig.generatorVersion;
        if (generatorVersion == null ||
            generatorVersion.major != sdk.version.major ||
            generatorVersion.minor != sdk.version.minor) {
          log.fine('The Dart SDK was updated since last package resolution.');
          return false;
        }
        return true;
      }

      final packageConfigStat = tryStatFile(packageConfigPath);
      if (packageConfigStat == null) {
        log.fine('No $packageConfigPath file found".\n');
        return null;
      }
      final flutter = FlutterSdk();
      // If Flutter has moved since last invocation, we want to have new
      // sdk-packages, and therefore do a new resolution.
      //
      // This also counts if Flutter was introduced or removed.
      final flutterRoot = flutter.rootDirectory == null
          ? null
          : p.toUri(p.absolute(flutter.rootDirectory!)).toString();
      if (packageConfig.additionalProperties['flutterRoot'] != flutterRoot) {
        log.fine('Flutter has moved since last invocation.');
        return null;
      }
      if (packageConfig.additionalProperties['flutterVersion'] !=
          (flutter.isAvailable ? null : flutter.version)) {
        log.fine('Flutter has updated since last invocation.');
        return null;
      }
      // If the pub cache was moved we should have a new resolution.
      final rootCacheUrl = p.toUri(p.absolute(cache.rootDir)).toString();
      if (packageConfig.additionalProperties['pubCache'] != rootCacheUrl) {
        log.fine(
          'The pub cache has moved from ${packageConfig.additionalProperties['pubCache']} to $rootCacheUrl since last invocation.',
        );
        return null;
      }
      // If the Dart sdk was updated we want a new resolution.
      if (!isPackageConfigGeneratedBySameDartSdk()) {
        return null;
      }
      final lockFileStat = tryStatFile(lockFilePath);
      if (lockFileStat == null) {
        log.fine('No $lockFilePath file found.');
        return null;
      }

      final lockFileModified = lockFileStat.modified;
      var lockfileNewerThanPubspecs = true;

      // Check that all packages in packageConfig exist and their pubspecs have
      // not been updated since the lockfile was written.
      for (var package in packageConfig.packages) {
        final pubspecPath = p.normalize(
          p.join(
            '.dart_tool',
            package.rootUri
                // Important to use `toFilePath()` here rather than `path`, as it handles Url-decoding.
                .toFilePath(),
            'pubspec.yaml',
          ),
        );
        if (p.isWithin(cache.rootDir, pubspecPath)) {
          continue;
        }
        final pubspecStat = tryStatFile(pubspecPath);
        if (pubspecStat == null) {
          log.fine('Could not find `$pubspecPath`');
          // A dependency is missing - do a full new resolution.
          return null;
        }

        if (pubspecStat.modified.isAfter(lockFileModified)) {
          log.fine('`$pubspecPath` is newer than `$lockFilePath`');
          lockfileNewerThanPubspecs = false;
          break;
        }
        final pubspecOverridesPath =
            p.join(package.rootUri.path, 'pubspec_overrides.yaml');
        final pubspecOverridesStat = tryStatFile(pubspecOverridesPath);
        if (pubspecOverridesStat != null) {
          // This will wrongly require you to reresolve if a
          // `pubspec_overrides.yaml` in a path-dependency is updated. That
          // seems acceptable.
          if (pubspecOverridesStat.modified.isAfter(lockFileModified)) {
            log.fine('`$pubspecOverridesPath` is newer than `$lockFilePath`');
            lockfileNewerThanPubspecs = false;
          }
        }
      }
      var touchedLockFile = false;
      late final lockFile = _loadLockFile(lockFilePath, cache);
      late final root = Package.load(
        dir,
        loadPubspec: Pubspec.loadRootWithSources(cache.sources),
      );

      if (!lockfileNewerThanPubspecs) {
        if (isLockFileUpToDate(lockFile, root)) {
          touch(lockFilePath);
          touchedLockFile = true;
        } else {
          return null;
        }
      }

      if (touchedLockFile ||
          lockFileModified.isAfter(packageConfigStat.modified)) {
        log.fine('`$lockFilePath` is newer than `$packageConfigPath`');
        if (isPackageConfigUpToDate(packageConfig, lockFile, root)) {
          touch(packageConfigPath);
        } else {
          return null;
        }
      }
      return packageConfig;
    }

    switch (isResolutionUpToDate()) {
      case null:
        final entrypoint = Entrypoint(
          dir, cache,
          // [ensureUpToDate] is also used for entries in 'global_packages/'
          checkInCache: false,
        );
        if (onlyOutputWhenTerminal) {
          await log.errorsOnlyUnlessTerminal(() async {
            await entrypoint.acquireDependencies(
              SolveType.get,
              summaryOnly: summaryOnly,
            );
          });
        } else {
          await entrypoint.acquireDependencies(
            SolveType.get,
            summaryOnly: summaryOnly,
          );
        }
        return entrypoint.packageConfig;
      case final PackageConfig packageConfig:
        log.fine('Package Config up to date.');
        return packageConfig;
    }
  }

  /// We require an SDK constraint lower-bound as of Dart 2.12.0
  ///
  /// We don't allow unknown sdks.
  void _checkSdkConstraint(String pubspecPath, Pubspec pubspec) {
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

  /// Setting the `PUB_SUMMARY_ONLY` environment variable to anything but '0'
  /// will result in [acquireDependencies] to only print a summary of the
  /// results.
  bool get _summaryOnlyEnvironment =>
      (Platform.environment['PUB_SUMMARY_ONLY'] ?? '0') != '0';

  /// Returns true if the packages in [newLockFile] and [previousLockFile] are
  /// all the same, meaning:
  ///  * same set of package-names
  ///  * for each package
  ///    * same version number
  ///    * same resolved description (same content-hash, git hash, path)
  bool _lockfilesMatch(LockFile previousLockFile, LockFile newLockFile) {
    if (previousLockFile.packages.length != newLockFile.packages.length) {
      return false;
    }
    for (final package in newLockFile.packages.values) {
      final oldPackage = previousLockFile.packages[package.name];
      if (oldPackage == null) return false; // Package added to resolution.
      if (oldPackage.version != package.version) return false;
      if (oldPackage.description != package.description) return false;
    }
    return true;
  }

  /// Remove any `pubspec.lock` or `.dart_tool/package_config.json` files in
  /// workspace packages that are not the root package.
  ///
  /// This is to avoid surprises if a package is turned into a workspace member
  /// but still has an old package config or lockfile.
  void _removeStrayLockAndConfigFiles() {
    for (final package in workspaceRoot.transitiveWorkspace) {
      if (package.pubspec.resolution == Resolution.workspace) {
        deleteEntry(p.join(package.dir, 'pubspec.lock'));
        deleteEntry(p.join(package.dir, '.dart_tool', 'package_config.json'));
      }
    }
  }

  /// Returns a list of changes to constraints of workspace pubspecs updated to
  /// have their lower bound match the version in [packageVersions] (or
  /// `this.lockFile`).
  ///
  /// The return value for each workspace package is a mapping from the original
  /// package range to the updated.
  ///
  /// If packages to update where given in [packagesToUpgrade], only those are
  /// tightened. Otherwise all packages are tightened.
  ///
  /// If a dependency has already been updated in [existingChanges], the update
  /// will apply on top of that change (eg. preserving the new upper bound).
  Map<Package, Map<PackageRange, PackageRange>> tighten({
    List<String> packagesToUpgrade = const [],
    Map<Package, Map<PackageRange, PackageRange>> existingChanges = const {},
    List<PackageId>? packageVersions,
  }) {
    final result = {...existingChanges};

    final toTighten = <(Package, PackageRange)>[];

    for (final package in workspaceRoot.transitiveWorkspace) {
      if (packagesToUpgrade.isEmpty) {
        for (final range in [
          ...package.dependencies.values,
          ...package.devDependencies.values,
        ]) {
          toTighten.add((package, range));
        }
      } else {
        for (final packageToUpgrade in packagesToUpgrade) {
          final range = package.dependencies[packageToUpgrade] ??
              package.devDependencies[packageToUpgrade];
          if (range != null) {
            toTighten.add((package, range));
          }
        }
      }
    }

    for (final (package, range) in toTighten) {
      final changesForPackage = result[package] ??= {};
      final constraint = (changesForPackage[range] ?? range).constraint;
      final resolvedVersion =
          (packageVersions?.firstWhere((p) => p.name == range.name) ??
                  lockFile.packages[range.name])!
              .version;
      if (range.source is HostedSource && constraint.isAny) {
        changesForPackage[range] = range
            .toRef()
            .withConstraint(VersionConstraint.compatibleWith(resolvedVersion));
      } else if (constraint is VersionRange) {
        final min = constraint.min;
        if (min != null && min < resolvedVersion) {
          changesForPackage[range] = range.toRef().withConstraint(
                VersionRange(
                  min: resolvedVersion,
                  max: constraint.max,
                  includeMin: true,
                  includeMax: constraint.includeMax,
                ).asCompatibleWithIfPossible(),
              );
        }
      }
    }
    return result;
  }

  /// Unless [dryRun], loads `pubspec.yaml` of each [package] in [changeSet] and applies the
  /// changes to its (dev)-dependencies using yaml_edit to preserve textual structure.
  ///
  /// Outputs a summary of changes done or would have been done if not [dryRun].
  void applyChanges(ChangeSet changeSet, bool dryRun) {
    if (!dryRun) {
      for (final package in workspaceRoot.transitiveWorkspace) {
        final changesForPackage = changeSet[package];
        if (changesForPackage == null || changesForPackage.isEmpty) {
          continue;
        }
        final yamlEditor = YamlEditor(readTextFile(package.pubspecPath));
        final deps = package.dependencies.keys;

        for (final change in changesForPackage.values) {
          final section =
              deps.contains(change.name) ? 'dependencies' : 'dev_dependencies';
          yamlEditor.update(
            [section, change.name],
            pubspecDescription(change, cache, package),
          );
        }
        writeTextFile(package.pubspecPath, yamlEditor.toString());
      }
    }
    _outputChangeSummary(changeSet, dryRun: dryRun);
  }

  /// Outputs a summary of [changeSet].
  void _outputChangeSummary(
    ChangeSet changeSet, {
    required bool dryRun,
  }) {
    if (workspaceRoot.workspaceChildren.isEmpty) {
      final changesToWorkspaceRoot = changeSet[workspaceRoot] ?? {};
      if (changesToWorkspaceRoot.isEmpty) {
        final wouldBe = dryRun ? 'would be made to' : 'to';
        log.message('\nNo changes $wouldBe pubspec.yaml!');
      } else {
        final changed = dryRun ? 'Would change' : 'Changed';
        log.message('\n$changed ${changesToWorkspaceRoot.length} '
            '${pluralize('constraint', changesToWorkspaceRoot.length)} in pubspec.yaml:');
        changesToWorkspaceRoot.forEach((from, to) {
          log.message('  ${from.name}: ${from.constraint} -> ${to.constraint}');
        });
      }
    } else {
      if (changeSet.isEmpty) {
        final wouldBe = dryRun ? 'would be made to' : 'to';
        log.message('\nNo changes $wouldBe any pubspec.yaml!');
      }
      for (final package in workspaceRoot.transitiveWorkspace) {
        final changesToPackage = changeSet[package] ?? {};
        if (changesToPackage.isEmpty) continue;
        final changed = dryRun ? 'Would change' : 'Changed';
        log.message('\n$changed ${changesToPackage.length} '
            '${pluralize('constraint', changesToPackage.length)} in ${package.pubspecPath}:');
        changesToPackage.forEach((from, to) {
          log.message('  ${from.name}: ${from.constraint} -> ${to.constraint}');
        });
      }
    }
  }
}

/// For each package in a workspace, a set of changes to dependencies.
typedef ChangeSet = Map<Package, Map<PackageRange, PackageRange>>;
