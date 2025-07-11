// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

import 'command_runner.dart';
import 'entrypoint.dart';
import 'exceptions.dart';
import 'executable.dart' as exec;
import 'io.dart';
import 'language_version.dart';
import 'lock_file.dart';
import 'log.dart' as log;
import 'package.dart';
import 'package_name.dart';
import 'pubspec.dart';
import 'sdk.dart';
import 'sdk/dart.dart';
import 'solver.dart';
import 'solver/incompatibility_cause.dart';
import 'solver/report.dart';
import 'source/cached.dart';
import 'source/git.dart';
import 'source/hosted.dart';
import 'source/path.dart';
import 'source/root.dart';
import 'source/sdk.dart';
import 'system_cache.dart';
import 'utils.dart';

/// Maintains the set of packages that have been globally activated.
///
/// These have been hand-chosen by the user to make their executables in bin/
/// available to the entire system. This lets them access them even when the
/// current working directory is not inside another entrypoint package.
///
/// Only one version of a given package name can be globally activated at a
/// time. Activating a different version of a package will deactivate the
/// previous one.
///
/// This handles packages from uncached and cached sources a little differently.
/// For a cached source, the package is physically in the user's pub cache and
/// we don't want to mess with it by putting a lockfile in there. Instead, when
/// we activate the package, we create a full lockfile and put it in the
/// "global_packages" directory. It's named `"<package>.lock"`. Unlike a normal
/// lockfile, it also contains an entry for the root package itself, so that we
/// know the version and description that was activated.
///
/// Uncached packages (i.e. "path" packages) are somewhere else on the user's
/// local file system and can have a lockfile directly in place. (And, in fact,
/// we want to ensure we honor the user's lockfile there.) To activate it, we
/// just need to know where that package directory is. For that, we create a
/// lockfile that *only* contains the root package's [PackageId] -- basically
/// just the path to the directory where the real lockfile lives.
class GlobalPackages {
  /// The [SystemCache] containing the global packages.
  final SystemCache cache;

  /// The directory where the lockfiles for activated packages are stored.
  String get _directory => p.join(cache.rootDir, 'global_packages');

  String _packageDir(String packageName) => p.join(_directory, packageName);

  /// The directory where binstubs for global package executables are stored.
  String get _binStubDir => p.join(cache.rootDir, 'bin');

  /// Creates a new global package registry backed by the given directory on
  /// the user's file system.
  ///
  /// The directory may not physically exist yet. If not, this will create it
  /// when needed.
  GlobalPackages(this.cache);

  /// Caches the package located in the Git repository [repo] and makes it the
  /// active global version.
  ///
  /// [executables] is the names of the executables that should have binstubs.
  /// If `null`, all executables in the package will get binstubs. If empty, no
  /// binstubs will be created.
  ///
  /// If [overwriteBinStubs] is `true`, any binstubs that collide with
  /// existing binstubs in other packages will be overwritten by this one's.
  /// Otherwise, the previous ones will be preserved.
  Future<void> activateGit(
    String repo,
    List<String>? executables, {
    required bool overwriteBinStubs,
    String? path,
    String? ref,
    String? tagPattern,
  }) async {
    final name = await cache.git.getPackageNameFromRepo(
      repo,
      ref,
      path,
      cache,
      relativeTo: p.current,
      tagPattern: tagPattern,
    );

    // TODO(nweiz): Add some special handling for git repos that contain path
    // dependencies. Their executables shouldn't be cached, and there should
    // be a mechanism for redoing dependency resolution if a path pubspec has
    // changed (see also issue 20499).
    PackageRef packageRef;
    try {
      packageRef = cache.git.parseRef(
        name,
        {
          'url': repo,
          if (path != null) 'path': path,
          if (ref != null) 'ref': ref,
        },
        containingDescription: ResolvedRootDescription.fromDir(p.current),
        languageVersion: LanguageVersion.fromVersion(sdk.version),
      );
    } on FormatException catch (e) {
      throw ApplicationException(e.message);
    }
    await _installInCache(
      packageRef.withConstraint(VersionConstraint.any),
      executables,
      overwriteBinStubs: overwriteBinStubs,
    );
  }

  Package packageForConstraint(PackageRange dep, String dir) {
    return Package(
      Pubspec(
        'pub global activate',
        dependencies: [dep],
        sources: cache.sources,
        sdkConstraints: {
          'dart': SdkConstraint.interpretDartSdkConstraint(
            VersionConstraint.parse('>=2.12.0'),
            defaultUpperBoundConstraint: null,
          ),
        },
      ),
      dir,
      [],
    );
  }

  /// Finds the latest version of the hosted package that matches [range] and
  /// makes it the active global version.
  ///
  /// [executables] is the names of the executables that should have binstubs.
  /// If `null`, all executables in the package will get binstubs. If empty, no
  /// binstubs will be created.
  ///
  /// if [overwriteBinStubs] is `true`, any binstubs that collide with existing
  /// binstubs in other packages will be overwritten by this one's. Otherwise,
  /// the previous ones will be preserved.
  ///
  /// [url] is an optional custom pub server URL. If not null, the package to be
  /// activated will be fetched from this URL instead of the default pub URL.
  Future<void> activateHosted(
    PackageRange range,
    List<String>? executables, {
    required bool overwriteBinStubs,
    String? url,
  }) async {
    await _installInCache(
      range,
      executables,
      overwriteBinStubs: overwriteBinStubs,
    );
  }

  void _testForHooks(Package package, String activatedPackageName) {
    final prelude =
        (package.name == activatedPackageName)
            ? 'Package $activatedPackageName uses hooks.'
            : 'The dependency of $activatedPackageName, '
                '${package.name} uses hooks.';
    if (fileExists(p.join(package.dir, 'hooks', 'build.dart'))) {
      fail('''
$prelude

You currently cannot `global activate` packages relying on hooks.

Follow progress in https://github.com/dart-lang/sdk/issues/60889.
''');
    }
  }

  /// Makes the local package at [path] globally active.
  ///
  /// [executables] is the names of the executables that should have binstubs.
  /// If `null`, all executables in the package will get binstubs. If empty, no
  /// binstubs will be created.
  ///
  /// if [overwriteBinStubs] is `true`, any binstubs that collide with
  /// existing binstubs in other packages will be overwritten by this one's.
  /// Otherwise, the previous ones will be preserved.
  Future<void> activatePath(
    String path,
    List<String>? executables, {
    required bool overwriteBinStubs,
  }) async {
    final entrypoint = Entrypoint(path, cache);

    // Get the package's dependencies.
    await entrypoint.acquireDependencies(SolveType.get);
    final activatedPackage = entrypoint.workPackage;
    final name = activatedPackage.name;
    for (final package in (await entrypoint.packageGraph)
        .transitiveDependencies(
          name,
          followDevDependenciesFromPackage: false,
        )) {
      _testForHooks(package, name);
    }
    _describeActive(name, cache);

    // Write a lockfile that points to the local package.
    final fullPath = canonicalize(activatedPackage.dir);
    final id = cache.path.idFor(
      name,
      activatedPackage.version,
      fullPath,
      p.current,
    );

    final tempDir = cache.createTempDir();
    // TODO(rnystrom): Look in "bin" and display list of binaries that
    // user can run.
    LockFile(
      [id],
      mainDependencies: {id.name},
    ).writeToFile(p.join(tempDir, 'pubspec.lock'), cache);

    tryDeleteEntry(_packageDir(name));
    tryRenameDir(tempDir, _packageDir(name));

    _updateBinStubs(
      entrypoint,
      activatedPackage,
      executables,
      overwriteBinStubs: overwriteBinStubs,
    );
    log.message('Activated ${_formatPackage(id)}.');
  }

  /// Installs the package [dep] and its dependencies into the system cache.
  ///
  /// If [silent] less logging will be printed.
  Future<void> _installInCache(
    PackageRange dep,
    List<String>? executables, {
    required bool overwriteBinStubs,
    bool silent = false,
  }) async {
    final name = dep.name;
    final originalLockFile = _describeActive(name, cache);

    final tempDir = cache.createTempDir();
    // Create a dummy package with just [dep] so we can do resolution on it.
    final root = packageForConstraint(dep, tempDir);

    // Resolve it and download its dependencies.
    SolveResult result;
    try {
      result = await log.spinner(
        'Resolving dependencies',
        () => resolveVersions(SolveType.get, cache, root),
        condition: !silent,
      );
    } on SolveFailure catch (error) {
      for (var incompatibility
          in error.incompatibility.externalIncompatibilities) {
        if (incompatibility.cause is! NoVersionsIncompatibilityCause) continue;
        if (incompatibility.terms.single.package.name != name) continue;
        // If the SolveFailure is caused by [dep] not
        // being available, report that as a [dataError].
        dataError(error.toString());
      }
      rethrow;
    }

    // We want the entrypoint to be rooted at 'dep' not the dummy-package.
    result.packages.removeWhere((id) => id.name == 'pub global activate');

    final lockFile = await result.downloadCachedPackages(cache);

    // Because we know that the dummy package never is a workspace we can
    // iterate all packages.
    for (final package in result.packages) {
      _testForHooks(
        // TODO(sigurdm): refactor PackageGraph to make it possible to query
        // without loading the entrypoint.
        Package(
          result.pubspecs[package.name]!,
          cache.getDirectory(package),
          [],
        ),
        name,
      );
    }

    final sameVersions =
        originalLockFile != null && originalLockFile.samePackageIds(lockFile);

    final id = lockFile.packages[name]!;
    if (sameVersions) {
      log.message('''
The package $name is already activated at newest available version.
To recompile executables, first run `$topLevelProgram pub global deactivate $name`.
''');
    } else {
      // Only precompile binaries if we have a new resolution.
      if (!silent) {
        await SolveReport(
          SolveType.get,
          null,
          root.pubspec,
          root.pubspec.dependencyOverrides,
          originalLockFile ?? LockFile.empty(),
          lockFile,
          result.availableVersions,
          cache,
          dryRun: false,
          quiet: false,
          enforceLockfile: false,
        ).show(summary: false);
      }

      lockFile.writeToFile(p.join(tempDir, 'pubspec.lock'), cache);

      final packageDir = _packageDir(name);
      tryDeleteEntry(packageDir);
      tryRenameDir(tempDir, packageDir);

      // Load the package graph from [result] so we don't need to re-parse all
      // the pubspecs.
      final entrypoint = Entrypoint.global(
        packageForConstraint(dep, packageDir),
        lockFile,
        cache,
        solveResult: result,
      );

      await entrypoint.writePackageConfigFiles();

      await entrypoint.precompileExecutables();
    }

    final entrypoint = Entrypoint.global(
      packageForConstraint(dep, _packageDir(dep.name)),
      lockFile,
      cache,
      solveResult: result,
    );
    _updateBinStubs(
      entrypoint,
      cache.load(entrypoint.lockFile.packages[dep.name]!),
      executables,
      overwriteBinStubs: overwriteBinStubs,
    );
    if (!silent) log.message('Activated ${_formatPackage(id)}.');
  }

  /// Shows the user the currently active package with [name], if any.
  LockFile? _describeActive(String name, SystemCache cache) {
    final lower = name.toLowerCase();
    if (name != lower) {
      fail('''
You can only activate packages with lower-case names.

Did you mean `$lower`?
''');
    }
    final LockFile lockFile;
    final lockFilePath = _getLockFilePath(name);
    try {
      lockFile = LockFile.load(lockFilePath, cache.sources);
    } on IOException {
      // Couldn't read the lock file. It probably doesn't exist.
      return null;
    }

    final id = lockFile.packages[name];
    if (id == null) {
      fail('''
Could not find `$name` in `$lockFilePath`.
Your Pub cache might be corrupted.

Consider `$topLevelProgram pub global deactivate $name`''');
    }
    final description = id.description.description;

    if (description is GitDescription) {
      log.message(
        'Package ${log.bold(name)} is currently active from Git '
        'repository "${GitDescription.prettyUri(description.url)}".',
      );
    } else if (description is PathDescription) {
      log.message(
        'Package ${log.bold(name)} is currently active at path '
        '"${description.path}".',
      );
    } else {
      log.message(
        'Package ${log.bold(name)} is currently active at version '
        '${log.bold(id.version.toString())}.',
      );
    }
    return lockFile;
  }

  /// Deactivates a previously-activated package named [name].
  ///
  /// Returns `false` if no package with [name] was currently active.
  bool deactivate(String name) {
    final dir = p.join(_directory, name);
    if (!dirExists(_directory)) {
      return false;
    }
    // By listing all files instead of using only `dirExists` this check will
    // work on case-preserving file-systems.
    final files = listDir(_directory);
    if (!files.contains(dir)) {
      return false;
    }
    if (!dirExists(dir)) {
      // This can happen if `dir` was really a file.
      return false;
    }

    _deleteBinStubs(name);

    final lockFile = LockFile.load(_getLockFilePath(name), cache.sources);
    final id = lockFile.packages[name];
    if (id == null) {
      log.message('Removed package `$name`');
    } else {
      log.message('Deactivated package ${_formatPackage(id)}.');
    }
    deleteEntry(dir);

    return true;
  }

  /// Finds the active package with [name].
  ///
  /// Returns an [Entrypoint] loaded with the active package if found.
  Future<Entrypoint> find(String name) async {
    final lockFilePath = _getLockFilePath(name);
    final LockFile lockFile;
    try {
      lockFile = LockFile.load(lockFilePath, cache.sources);
    } on IOException {
      // If we couldn't read the lock file, it's not activated.
      dataError('No active package ${log.bold(name)}.');
    }

    final id = lockFile.packages[name]!;

    Entrypoint entrypoint;
    if (id.source is CachedSource) {
      // For cached sources, the package itself is in the cache and the
      // lockfile is the one we just loaded.
      entrypoint = Entrypoint.global(
        packageForConstraint(id.toRange(), _packageDir(id.name)),
        lockFile,
        cache,
      );
    } else {
      // For uncached sources (i.e. path), the ID just points to the real
      // directory for the package.
      entrypoint = Entrypoint(
        (id.description.description as PathDescription).path,
        cache,
      );
    }

    // Check that the SDK constraints the lockFile says we have are honored.
    lockFile.sdkConstraints.forEach((sdkName, constraint) {
      final sdk = sdks[sdkName];
      if (sdk == null) {
        dataError(
          '${log.bold(name)} as globally activated requires '
          'unknown SDK "$name".',
        );
      } else if (sdkName == 'dart') {
        if (constraint.effectiveConstraint.allows((sdk as DartSdk).version)) {
          return;
        }
        dataError('''
${log.bold(name)} as globally activated doesn't support Dart ${sdk.version}.

try:
`$topLevelProgram pub global activate $name` to reactivate.
''');
      } else {
        dataError(
          '${log.bold(name)} as globally activated requires the '
          '${sdk.name} SDK, which is unsupported for global executables.',
        );
      }
    });

    return entrypoint;
  }

  /// Runs [executable] with [args].
  ///
  /// If [executable] is available in its built form, that will be
  /// recompiled if the SDK has been upgraded since it was first compiled and
  /// then run. Otherwise, it will be run from source.
  ///
  /// If [enableAsserts] is true, the program is run with assertions enabled.
  ///
  /// Returns the exit code from the executable.
  Future<int> runExecutable(
    Entrypoint entrypoint,
    exec.Executable executable,
    List<String> args, {
    bool enableAsserts = false,
    required Future<void> Function(exec.Executable) recompile,
    List<String> vmArgs = const [],
    required bool alwaysUseSubprocess,
  }) async {
    return await exec.runExecutable(
      entrypoint,
      executable,
      args,
      enableAsserts: enableAsserts,
      recompile: (exectuable) async {
        final root = entrypoint.workspaceRoot;
        final name = exectuable.package;

        // When recompiling we re-resolve it and download its dependencies. This
        // is mainly to protect from the case where the sdk was updated, and
        // that causes some incompatibilities. (could be the new sdk is outside
        // some package's environment constraint range, or that the sdk came
        // with incompatible versions of sdk packages).
        //
        // We use --enforce-lockfile semantics, because we want upgrading
        // globally activated packages to be conscious, and not a part of
        // running them.
        SolveResult result;
        try {
          result = await log.spinner(
            'Resolving dependencies',
            () => resolveVersions(
              SolveType.get,
              cache,
              root,
              lockFile: entrypoint.lockFile,
            ),
          );
        } on SolveFailure catch (e) {
          log.error(e.message);
          fail('''The package `$name` as currently activated cannot resolve.

Try reactivating the package.
`$topLevelProgram pub global activate $name`          
''');
        }
        // We want the entrypoint to be rooted at 'dep' not the dummy-package.
        result.packages.removeWhere((id) => id.name == 'pub global activate');

        final newLockFile = await result.downloadCachedPackages(cache);
        final report = SolveReport(
          SolveType.get,
          entrypoint.workspaceRoot.dir,
          entrypoint.workspaceRoot.pubspec,
          entrypoint.workspaceRoot.allOverridesInWorkspace,
          entrypoint.lockFile,
          newLockFile,
          result.availableVersions,
          cache,
          dryRun: true,
          enforceLockfile: true,
          quiet: false,
        );
        await report.show(summary: true);

        final sameVersions = entrypoint.lockFile.samePackageIds(newLockFile);

        if (!sameVersions) {
          if (newLockFile.packages.values.any((p) {
            return p.source is SdkSource &&
                p.version != entrypoint.lockFile.packages[p.name]?.version;
          })) {
            // More specific error message for the case of a version match with
            // an sdk package.
            dataError('''
The current activation of `$name` is not compatible with your current SDK.

Try reactivating the package.
`$topLevelProgram pub global activate $name`
''');
          } else {
            dataError('''
The current activation of `$name` cannot resolve to the same set of dependencies.

Try reactivating the package.
`$topLevelProgram pub global activate $name`
''');
          }
        }
        await recompile(exectuable);
        _refreshBinStubs(entrypoint, executable);
      },
      vmArgs: vmArgs,
      alwaysUseSubprocess: alwaysUseSubprocess,
    );
  }

  /// Gets the path to the lock file for an activated cached package with
  /// [name].
  String _getLockFilePath(String name) =>
      p.join(_directory, name, 'pubspec.lock');

  /// Shows the user a formatted list of globally activated packages.
  void listActivePackages() {
    if (!dirExists(_directory)) return;

    listDir(_directory).map(_loadPackageId).toList()
      ..sort((id1, id2) => id1.name.compareTo(id2.name))
      ..forEach((id) => log.message(_formatPackage(id)));
  }

  /// Returns the [PackageId] for the globally-activated package at [path].
  ///
  /// [path] should be a path within [_directory]. It can either be an old-style
  /// path to a single lockfile or a new-style path to a directory containing a
  /// lockfile.
  PackageId _loadPackageId(String path) {
    final name = p.basenameWithoutExtension(path);
    if (!fileExists(path)) path = p.join(path, 'pubspec.lock');

    final id =
        LockFile.load(p.join(_directory, path), cache.sources).packages[name];

    if (id == null) {
      throw FormatException(
        "Pubspec for activated package $name didn't "
        'contain an entry for itself.',
      );
    }

    return id;
  }

  /// Returns formatted string representing the package [id].
  String _formatPackage(PackageId id) {
    final description = id.description.description;
    if (description is GitDescription) {
      final url = GitDescription.prettyUri(description.url);
      return '${log.bold(id.name)} ${id.version} from Git repository "$url"';
    } else if (description is PathDescription) {
      final path = description.path;
      return '${log.bold(id.name)} ${id.version} at path "$path"';
    } else {
      return '${log.bold(id.name)} ${id.version}';
    }
  }

  /// Repairs any corrupted globally-activated packages and their binstubs.
  ///
  /// Returns a pair of two lists of strings. The first indicates which packages
  /// were successfully re-activated; the second indicates which failed.
  Future<(List<String> successes, List<String> failures)>
  repairActivatedPackages() async {
    final executables = <String, List<String>>{};
    if (dirExists(_binStubDir)) {
      for (var entry in listDir(_binStubDir)) {
        try {
          final binstub = readTextFile(entry);
          final package = _binStubProperty(binstub, 'Package');
          if (package == null) {
            throw ApplicationException("No 'Package' property.");
          }

          final executable = _binStubProperty(binstub, 'Executable');
          if (executable == null) {
            throw ApplicationException("No 'Executable' property.");
          }

          executables.putIfAbsent(package, () => []).add(executable);
        } catch (error, stackTrace) {
          log.error(
            'Error reading binstub for '
            '"${p.basenameWithoutExtension(entry)}"',
            error,
            stackTrace,
          );

          tryDeleteEntry(entry);
        }
      }
    }

    final successes = <String>[];
    final failures = <String>[];
    if (dirExists(_directory)) {
      for (var entry in listDir(_directory)) {
        PackageId? id;
        try {
          id = _loadPackageId(entry);
          log.message('Reactivating ${log.bold(id.name)} ${id.version}...');

          final entrypoint = await find(id.name);
          final packageExecutables = executables.remove(id.name) ?? [];

          if (entrypoint.isCached) {
            deleteEntry(_packageDir(id.name));
            await _installInCache(
              id.toRange(),
              packageExecutables,
              overwriteBinStubs: true,
              silent: true,
            );
          } else {
            await activatePath(
              entrypoint.workspaceRoot.dir,
              packageExecutables,
              overwriteBinStubs: true,
            );
          }
          successes.add(id.name);
        } catch (error, stackTrace) {
          var message =
              'Failed to reactivate '
              '${log.bold(p.basenameWithoutExtension(entry))}';
          if (id != null) {
            message += ' ${id.version}';
            if (id.source is! HostedSource) message += ' from ${id.source}';
          }

          log.error(message, error, stackTrace);
          failures.add(p.basenameWithoutExtension(entry));

          tryDeleteEntry(entry);
        }
      }
    }

    if (executables.isNotEmpty) {
      final message = StringBuffer(
        'Binstubs exist for non-activated '
        'packages:\n',
      );
      executables.forEach((package, executableNames) {
        for (var executable in executableNames) {
          deleteEntry(p.join(_binStubDir, executable));
        }

        message.writeln(
          '  From ${log.bold(package)}: '
          '${toSentence(executableNames)}',
        );
      });
      log.error(message.toString());
    }

    return (successes, failures);
  }

  /// Rewrites all binstubs that refer to [executable] of [entrypoint].
  ///
  /// This is meant to be called after a recompile due to eg. outdated
  /// snapshots.
  void _refreshBinStubs(Entrypoint entrypoint, exec.Executable executable) {
    if (!dirExists(_binStubDir)) return;
    for (var file in listDir(_binStubDir, includeDirs: false)) {
      final contents = readTextFile(file);
      final binStubPackage = _binStubProperty(contents, 'Package');
      final binStubScript = _binStubProperty(contents, 'Script');
      if (binStubPackage == null || binStubScript == null) {
        log.fine('Could not parse binstub $file:\n$contents');
        continue;
      }
      if (binStubPackage == executable.package &&
          binStubScript ==
              p.basenameWithoutExtension(executable.relativePath)) {
        log.fine('Replacing old binstub $file');
        _createBinStub(
          activatedPackage(entrypoint),
          p.basenameWithoutExtension(file),
          binStubScript,
          overwrite: true,
          isRefreshingBinstub: true,
          snapshot: executable.pathOfGlobalSnapshot(
            entrypoint.workspaceRoot.dir,
          ),
        );
      }
    }
  }

  /// Updates the binstubs for [package].
  ///
  /// A binstub is a little shell script in `PUB_CACHE/bin` that runs an
  /// executable from a globally activated package. This removes any old
  /// binstubs from the previously activated version of the package and
  /// (optionally) creates new ones for the executables listed in the package's
  /// pubspec.
  ///
  /// [executables] is the names of the executables that should have binstubs.
  /// If `null`, all executables in the package will get binstubs. If empty, no
  /// binstubs will be created.
  ///
  /// If [overwriteBinStubs] is `true`, any binstubs that collide with existing
  /// binstubs in other packages will be overwritten by this one's. Otherwise,
  /// the previous ones will be preserved.
  ///
  /// If [suggestIfNotOnPath] is `true` (the default), this will warn the user
  /// if the bin directory isn't on their path.
  void _updateBinStubs(
    Entrypoint entrypoint,
    Package package,
    List<String>? executables, {
    required bool overwriteBinStubs,
    bool suggestIfNotOnPath = true,
  }) {
    // Remove any previously activated binstubs for this package, in case the
    // list of executables has changed.
    _deleteBinStubs(package.name);

    if ((executables != null && executables.isEmpty) ||
        package.pubspec.executables.isEmpty) {
      return;
    }

    ensureDir(_binStubDir);

    final installed = <String>[];
    final collided = <String, String>{};
    final allExecutables = package.pubspec.executables.keys.sorted();
    for (var executable in allExecutables) {
      if (executables != null && !executables.contains(executable)) continue;

      final script = package.pubspec.executables[executable]!;

      final previousPackage = _createBinStub(
        package,
        executable,
        script,
        overwrite: overwriteBinStubs,
        isRefreshingBinstub: false,
        snapshot: entrypoint.pathOfSnapshot(
          exec.Executable.adaptProgramName(package.name, script),
        ),
      );
      if (previousPackage != null) {
        collided[executable] = previousPackage;

        if (!overwriteBinStubs) continue;
      }

      installed.add(executable);
    }

    if (installed.isNotEmpty) {
      final names = namedSequence('executable', installed.map(log.bold));
      log.message('Installed $names.');
    }

    // Show errors for any collisions.
    if (collided.isNotEmpty) {
      for (var command in collided.keys.sorted()) {
        if (overwriteBinStubs) {
          log.warning(
            'Replaced ${log.bold(command)} previously installed from '
            '${log.bold(collided[command].toString())}.',
          );
        } else {
          log.warning(
            'Executable ${log.bold(command)} was already installed '
            'from ${log.bold(collided[command].toString())}.',
          );
        }
      }

      if (!overwriteBinStubs) {
        log.warning(
          'Deactivate the other package(s) or activate '
          '${log.bold(package.name)} using --overwrite.',
        );
      }
    }

    // Show errors for any unknown executables.
    if (executables != null) {
      final unknown =
          executables
              .where((exe) => !package.pubspec.executables.keys.contains(exe))
              .sorted();
      if (unknown.isNotEmpty) {
        dataError("Unknown ${namedSequence('executable', unknown)}.");
      }
    }

    // Show errors for any missing scripts.
    // TODO(rnystrom): This can print false positives since a script may be
    // produced by a transformer. Do something better.
    final binFiles = package.executablePaths;
    for (var executable in installed) {
      final script = package.pubspec.executables[executable];
      final scriptPath = p.join('bin', '$script.dart');
      if (!binFiles.contains(scriptPath)) {
        log.warning(
          'Warning: Executable "$executable" runs "$scriptPath", '
          'which was not found in ${log.bold(package.name)}.',
        );
      }
    }

    if (suggestIfNotOnPath && installed.isNotEmpty) {
      _suggestIfNotOnPath(installed.first);
    }
  }

  /// Creates a binstub named [executable] that runs [script] from [package].
  ///
  /// If [overwrite] is `true`, this will replace an existing binstub with that
  /// name for another package.
  ///
  /// [snapshot] is a path to a snapshot file. If that snapshot exists the
  /// binstub will invoke that directly. Otherwise, it will run
  /// `pub global run`.
  ///
  /// If a collision occurs, returns the name of the package that owns the
  /// existing binstub. Otherwise returns `null`.
  String? _createBinStub(
    Package package,
    String executable,
    String script, {
    required bool overwrite,
    required String snapshot,
    required bool isRefreshingBinstub,
  }) {
    var binStubPath = p.join(_binStubDir, executable);
    if (Platform.isWindows) binStubPath += '.bat';

    String? previousPackage;
    if (!isRefreshingBinstub && fileExists(binStubPath)) {
      final contents = readTextFile(binStubPath);
      previousPackage = _binStubProperty(contents, 'Package');
      if (previousPackage == null) {
        log.fine('Could not parse binstub $binStubPath:\n$contents');
      } else if (!overwrite) {
        return previousPackage;
      }
    }
    // When running tests we want the binstub to invoke the current pub, not the
    // one from the sdk.
    final pubInvocation =
        runningFromTest ? Platform.script.toFilePath() : 'pub';

    final String binstub;
    // We need an absolute path since relative ones won't be relative to the
    // right directory when the user runs this.
    snapshot = p.absolute(snapshot);
    // Batch files behave in funky ways if they are modified while updating.
    // To ensure that the byte-offsets of everything stays the same even if the
    // snapshot filename changes we insert some padding in lines containing the
    // snapshot.
    // 260 is the maximal short path length on Windows. Hopefully that is
    // enough.
    final padding = ' ' * (260 - snapshot.length);
    if (Platform.isWindows) {
      binstub = '''
@echo off
rem This file was created by pub v${sdk.version}.
rem Package: ${package.name}
rem Version: ${package.version}
rem Executable: $executable
rem Script: $script
if exist "$snapshot" $padding(
  call dart "$snapshot" $padding%*
  rem The VM exits with code 253 if the snapshot version is out-of-date.
  rem If it is, we need to delete it and run "pub global" manually.
  if not errorlevel 253 (
    goto error
  )
  call dart $pubInvocation global run ${package.name}:$script %*
) else (
  call dart $pubInvocation global run ${package.name}:$script %*
)
goto eof
:error
exit /b %errorlevel%
:eof
''';
    } else {
      binstub = '''
#!/usr/bin/env sh
# This file was created by pub v${sdk.version}.
# Package: ${package.name}
# Version: ${package.version}
# Executable: $executable
# Script: $script
if [ -f $snapshot ]; then
  dart "$snapshot" "\$@"
  # The VM exits with code 253 if the snapshot version is out-of-date.
  # If it is, we need to delete it and run "pub global" manually.
  exit_code=\$?
  if [ \$exit_code != 253 ]; then
    exit \$exit_code
  fi
  dart $pubInvocation -v global run ${package.name}:$script "\$@"
else
  dart $pubInvocation global run ${package.name}:$script "\$@"
fi
''';
    }

    // Write the binstub to a temporary location, make it executable and move
    // it into place afterwards to avoid races.
    final tempDir = cache.createTempDir();
    try {
      final tmpPath = p.join(tempDir, p.basename(binStubPath));

      // Write this as the system encoding since the system is going to
      // execute it and it might contain non-ASCII characters in the
      // path names.
      writeTextFile(tmpPath, binstub, encoding: const SystemEncoding());

      if (Platform.isLinux || Platform.isMacOS) {
        // Make it executable.
        final result = Process.runSync('chmod', ['+x', tmpPath]);
        if (result.exitCode != 0) {
          // Couldn't make it executable so don't leave it laying around.
          fail(
            'Could not make "$tmpPath" executable (exit code '
            '${result.exitCode}):\n${result.stderr}',
          );
        }
      }
      File(tmpPath).renameSync(binStubPath);
    } finally {
      deleteEntry(tempDir);
    }

    return previousPackage;
  }

  /// Deletes all existing binstubs for [package].
  void _deleteBinStubs(String package) {
    if (!dirExists(_binStubDir)) return;

    for (var file in listDir(_binStubDir, includeDirs: false)) {
      final contents = readTextFile(file);
      final binStubPackage = _binStubProperty(contents, 'Package');
      if (binStubPackage == null) {
        log.fine('Could not parse binstub $file:\n$contents');
        continue;
      }

      if (binStubPackage == package) {
        log.fine('Deleting old binstub $file');
        deleteEntry(file);
      }
    }
  }

  /// Checks to see if the binstubs are on the user's PATH and, if not, suggests
  /// that the user add the directory to their PATH.
  ///
  /// [installed] should be the name of an installed executable that can be used
  /// to test whether accessing it on the path works.
  void _suggestIfNotOnPath(String installed) {
    if (Platform.isWindows) {
      // See if the shell can find one of the binstubs.
      // "\q" means return exit code 0 if found or 1 if not.
      final result = runProcessSync('where', [r'\q', '$installed.bat']);
      if (result.exitCode == 0) return;

      log.warning(
        "${log.yellow('Warning:')} Pub installs executables into "
        '${log.bold(_binStubDir)}, which is not on your path.\n'
        "You can fix that by adding that directory to your system's "
        '"Path" environment variable.\n'
        'A web search for "configure windows path" will show you how.',
      );
    } else {
      // See if the shell can find one of the binstubs.
      //
      // The "command" builtin is more reliable than the "which" executable. See
      // http://unix.stackexchange.com/questions/85249/why-not-use-which-what-to-use-then
      final result = runProcessSync('command', [
        '-v',
        installed,
      ], runInShell: true);
      if (result.exitCode == 0) return;

      var binDir = _binStubDir;
      if (binDir.startsWith(Platform.environment['HOME']!)) {
        binDir = p.join(
          r'$HOME',
          p.relative(binDir, from: Platform.environment['HOME']),
        );
      }
      final shellConfigFiles =
          Platform.isMacOS
              // zsh is default on mac - mention that first.
              ? '(.zshrc, .bashrc, .bash_profile, etc.)'
              : '(.bashrc, .bash_profile, .zshrc etc.)';
      log.warning(
        "${log.yellow('Warning:')} Pub installs executables into "
        '${log.bold(binDir)}, which is not on your path.\n'
        "You can fix that by adding this to your shell's config file "
        '$shellConfigFiles:\n'
        '\n'
        "  ${log.bold('export PATH="\$PATH":"$binDir"')}\n"
        '\n',
      );
    }
  }

  /// Returns the value of the property named [name] in the bin stub script
  /// [source].
  String? _binStubProperty(String source, String name) {
    final pattern = RegExp(RegExp.escape(name) + r': ([a-zA-Z0-9_-]+)');
    final match = pattern.firstMatch(source);
    return match == null ? null : match[1];
  }
}

/// The package that was activated.
///
/// * For path packages this is [Entrypoint.workspaceRoot].
/// * For cached packages this is the sole dependency of
///   [Entrypoint.workspaceRoot].
Package activatedPackage(Entrypoint entrypoint) {
  if (entrypoint.isCachedGlobal) {
    final dep = entrypoint.workspaceRoot.dependencies.keys.single;
    return entrypoint.cache.load(entrypoint.lockFile.packages[dep]!);
  } else {
    return entrypoint.workPackage;
  }
}
