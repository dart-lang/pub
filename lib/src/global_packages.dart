// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

import 'dart.dart' as dart;
import 'entrypoint.dart';
import 'exceptions.dart';
import 'executable.dart' as exe;
import 'http.dart' as http;
import 'io.dart';
import 'lock_file.dart';
import 'log.dart' as log;
import 'package.dart';
import 'package_name.dart';
import 'pubspec.dart';
import 'sdk.dart';
import 'solver.dart';
import 'solver/incompatibility_cause.dart';
import 'source/cached.dart';
import 'source/git.dart';
import 'source/hosted.dart';
import 'source/path.dart';
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
/// "global_packages" directory. It's named "<package>.lock". Unlike a normal
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
  /// The [features] map controls which features of the package to activate.
  ///
  /// If [overwriteBinStubs] is `true`, any binstubs that collide with
  /// existing binstubs in other packages will be overwritten by this one's.
  /// Otherwise, the previous ones will be preserved.
  Future activateGit(String repo, List<String> executables,
      {Map<String, FeatureDependency> features, bool overwriteBinStubs}) async {
    var name = await cache.git.getPackageNameFromRepo(repo);
    // Call this just to log what the current active package is, if any.
    _describeActive(name);

    // TODO(nweiz): Add some special handling for git repos that contain path
    // dependencies. Their executables shouldn't be cached, and there should
    // be a mechanism for redoing dependency resolution if a path pubspec has
    // changed (see also issue 20499).
    await _installInCache(
        cache.git.source
            .refFor(name, repo)
            .withConstraint(VersionConstraint.any)
            .withFeatures(features ?? const {}),
        executables,
        overwriteBinStubs: overwriteBinStubs);
  }

  /// Finds the latest version of the hosted package with [name] that matches
  /// [constraint] and makes it the active global version.
  ///
  /// The [features] map controls which features of the package to activate.
  ///
  /// [executables] is the names of the executables that should have binstubs.
  /// If `null`, all executables in the package will get binstubs. If empty, no
  /// binstubs will be created.
  ///
  /// if [overwriteBinStubs] is `true`, any binstubs that collide with
  /// existing binstubs in other packages will be overwritten by this one's.
  /// Otherwise, the previous ones will be preserved.
  ///
  /// [url] is an optional custom pub server URL. If not null, the package to be
  /// activated will be fetched from this URL instead of the default pub URL.
  Future activateHosted(
      String name, VersionConstraint constraint, List<String> executables,
      {Map<String, FeatureDependency> features,
      bool overwriteBinStubs,
      String url}) async {
    _describeActive(name);
    await _installInCache(
        cache.hosted.source
            .refFor(name, url: url)
            .withConstraint(constraint)
            .withFeatures(features ?? const {}),
        executables,
        overwriteBinStubs: overwriteBinStubs);
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
  Future activatePath(String path, List<String> executables,
      {bool overwriteBinStubs}) async {
    var entrypoint = Entrypoint(path, cache);

    // Get the package's dependencies.
    await entrypoint.acquireDependencies(SolveType.GET, precompile: true);
    var name = entrypoint.root.name;

    // Call this just to log what the current active package is, if any.
    _describeActive(name);

    // Write a lockfile that points to the local package.
    var fullPath = canonicalize(entrypoint.root.dir);
    var id = cache.path.source.idFor(name, entrypoint.root.version, fullPath);

    // TODO(rnystrom): Look in "bin" and display list of binaries that
    // user can run.
    _writeLockFile(name, LockFile([id]));

    var binDir = p.join(_directory, name, 'bin');
    if (dirExists(binDir)) deleteEntry(binDir);

    _updateBinStubs(entrypoint.root, executables,
        overwriteBinStubs: overwriteBinStubs);
    log.message('Activated ${_formatPackage(id)}.');
  }

  /// Installs the package [dep] and its dependencies into the system cache.
  Future _installInCache(PackageRange dep, List<String> executables,
      {bool overwriteBinStubs}) async {
    // Create a dummy package with just [dep] so we can do resolution on it.
    var root = Package.inMemory(Pubspec('pub global activate',
        dependencies: [dep], sources: cache.sources));

    // Resolve it and download its dependencies.
    //
    // TODO(nweiz): If this produces a SolveFailure that's caused by [dep] not
    // being available, report that as a [dataError].
    SolveResult result;
    try {
      result = await log.progress('Resolving dependencies',
          () => resolveVersions(SolveType.GET, cache, root));
    } on SolveFailure catch (error) {
      for (var incompatibility
          in error.incompatibility.externalIncompatibilities) {
        if (incompatibility.cause != IncompatibilityCause.noVersions) continue;
        if (incompatibility.terms.single.package.name != dep.name) continue;
        dataError(error.toString());
      }
      rethrow;
    }

    result.showReport(SolveType.GET);

    // Make sure all of the dependencies are locally installed.
    await Future.wait(result.packages.map((id) {
      return http.withDependencyType(root.dependencyType(id.name), () async {
        if (id.isRoot) return;

        var source = cache.source(id.source);
        if (source is CachedSource) await source.downloadToSystemCache(id);
      });
    }));

    var lockFile = result.lockFile;
    _writeLockFile(dep.name, lockFile);
    // TODO(sigurdm): Use [Entrypoint.writePackagesFiles] instead.
    final packagesFilePath = _getPackagesFilePath(dep.name);
    final packageConfigFilePath = _getPackageConfigFilePath(dep.name);
    writeTextFile(packagesFilePath, lockFile.packagesFile(cache));
    ensureDir(p.dirname(packageConfigFilePath));
    writeTextFile(
        packageConfigFilePath, await lockFile.packageConfigFile(cache));

    // Load the package graph from [result] so we don't need to re-parse all
    // the pubspecs.
    var entrypoint = Entrypoint.fromSolveResult(root, cache, result);
    var snapshots = await _precompileExecutables(entrypoint, dep.name);

    _updateBinStubs(entrypoint.packageGraph.packages[dep.name], executables,
        overwriteBinStubs: overwriteBinStubs, snapshots: snapshots);

    var id = lockFile.packages[dep.name];
    log.message('Activated ${_formatPackage(id)}.');
  }

  /// Precompiles the executables for [packageName] and saves them in the global
  /// cache.
  ///
  /// Returns a map from executable name to path for the snapshots that were
  /// successfully precompiled.
  Future<Map<String, String>> _precompileExecutables(
      Entrypoint entrypoint, String packageName) {
    return log.progress('Precompiling executables', () async {
      var binDir = p.join(_directory, packageName, 'bin');
      cleanDir(binDir);

      final packagesFilePath = _getPackagesFilePath(packageName);
      final packageConfigFilePath = _getPackageConfigFilePath(packageName);
      if (!fileExists(packagesFilePath) || !fileExists(packageConfigFilePath)) {
        // TODO(sigurdm): Use [entrypoint.writePackagesFiles] instead.
        // The `.packages` file may not already exist if the global executable
        // has a 1.6-style lock file instead.
        // Similarly, the `.dart_tool/package_config.json` may not exist if the
        // global executable was activated before 2.6
        writeTextFile(
            packagesFilePath, entrypoint.lockFile.packagesFile(cache));
        ensureDir(p.dirname(packageConfigFilePath));
        writeTextFile(
          packageConfigFilePath,
          await entrypoint.lockFile.packageConfigFile(cache),
        );
      }

      // Try to avoid starting up an asset server to precompile packages if
      // possible. This is faster and produces better error messages.
      var package = entrypoint.packageGraph.packages[packageName];
      var precompiled = <String, String>{};
      await waitAndPrintErrors(package.executablePaths.map((path) async {
        var url = p.toUri(p.join(package.dir, path));
        var basename = p.basename(path);
        var snapshotPath = p.join(binDir, '$basename.snapshot.dart2');
        await dart.snapshot(url, snapshotPath,
            packagesFile: p.toUri(_getPackagesFilePath(package.name)),
            name: '${package.name}:${p.basenameWithoutExtension(path)}');
        precompiled[p.withoutExtension(basename)] = snapshotPath;
      }));
      return precompiled;
    });
  }

  /// Finishes activating package [package] by saving [lockFile] in the cache.
  void _writeLockFile(String package, LockFile lockFile) {
    ensureDir(p.join(_directory, package));

    // TODO(nweiz): This cleans up Dart 1.6's old lockfile location. Remove it
    // when Dart 1.6 is old enough that we don't think anyone will have these
    // lockfiles anymore (issue 20703).
    var oldPath = p.join(_directory, '$package.lock');
    if (fileExists(oldPath)) deleteEntry(oldPath);

    writeTextFile(_getLockFilePath(package), lockFile.serialize(cache.rootDir));
  }

  /// Shows the user the currently active package with [name], if any.
  void _describeActive(String name) {
    try {
      var lockFile = LockFile.load(_getLockFilePath(name), cache.sources);
      var id = lockFile.packages[name];

      var source = id.source;
      if (source is GitSource) {
        var url = source.urlFromDescription(id.description);
        log.message('Package ${log.bold(name)} is currently active from Git '
            'repository "$url".');
      } else if (source is PathSource) {
        var path = source.pathFromDescription(id.description);
        log.message('Package ${log.bold(name)} is currently active at path '
            '"$path".');
      } else {
        log.message('Package ${log.bold(name)} is currently active at version '
            '${log.bold(id.version)}.');
      }
    } on IOException {
      // If we couldn't read the lock file, it's not activated.
      return;
    }
  }

  /// Deactivates a previously-activated package named [name].
  ///
  /// Returns `false` if no package with [name] was currently active.
  bool deactivate(String name) {
    var dir = p.join(_directory, name);
    if (!dirExists(dir)) return false;

    _deleteBinStubs(name);

    var lockFile = LockFile.load(_getLockFilePath(name), cache.sources);
    var id = lockFile.packages[name];
    log.message('Deactivated package ${_formatPackage(id)}.');

    deleteEntry(dir);

    return true;
  }

  /// Finds the active package with [name].
  ///
  /// Returns an [Entrypoint] loaded with the active package if found.
  Entrypoint find(String name) {
    var lockFilePath = _getLockFilePath(name);
    LockFile lockFile;
    try {
      lockFile = LockFile.load(lockFilePath, cache.sources);
    } on IOException {
      var oldLockFilePath = p.join(_directory, '$name.lock');
      try {
        // TODO(nweiz): This looks for Dart 1.6's old lockfile location.
        // Remove it when Dart 1.6 is old enough that we don't think anyone
        // will have these lockfiles anymore (issue 20703).
        lockFile = LockFile.load(oldLockFilePath, cache.sources);
      } on IOException {
        // If we couldn't read the lock file, it's not activated.
        dataError('No active package ${log.bold(name)}.');
      }

      // Move the old lockfile to its new location.
      ensureDir(p.dirname(lockFilePath));
      File(oldLockFilePath).renameSync(lockFilePath);
    }

    // Remove the package itself from the lockfile. We put it in there so we
    // could find and load the [Package] object, but normally an entrypoint
    // doesn't expect to be in its own lockfile.
    var id = lockFile.packages[name];
    lockFile = lockFile.removePackage(name);

    var source = cache.source(id.source);
    Entrypoint entrypoint;
    if (source is CachedSource) {
      // For cached sources, the package itself is in the cache and the
      // lockfile is the one we just loaded.
      entrypoint = Entrypoint.inMemory(cache.load(id), lockFile, cache);
    } else {
      // For uncached sources (i.e. path), the ID just points to the real
      // directory for the package.
      entrypoint = Entrypoint(
          (id.source as PathSource).pathFromDescription(id.description), cache);
    }

    entrypoint.root.pubspec.sdkConstraints.forEach((sdkName, constraint) {
      var sdk = sdks[sdkName];
      if (sdk == null) {
        dataError('${log.bold(name)} ${entrypoint.root.version} requires '
            'unknown SDK "$name".');
      } else if (sdkName == 'dart') {
        if (constraint.allows(sdk.version)) return;
        dataError("${log.bold(name)} ${entrypoint.root.version} doesn't "
            'support Dart ${sdk.version}.');
      } else {
        dataError('${log.bold(name)} ${entrypoint.root.version} requires the '
            '${sdk.name} SDK, which is unsupported for global executables.');
      }
    });

    return entrypoint;
  }

  /// Runs [package]'s [executable] with [args].
  ///
  /// If [executable] is available in its precompiled form, that will be
  /// recompiled if the SDK has been upgraded since it was first compiled and
  /// then run. Otherwise, it will be run from source.
  ///
  /// If [enableAsserts] is true, the program is run with assertions enabled.
  ///
  /// Returns the exit code from the executable.
  Future<int> runExecutable(
      String package, String executable, Iterable<String> args,
      {bool enableAsserts = false}) {
    var entrypoint = find(package);
    return exe.runExecutable(
        entrypoint, package, p.join('bin', '$executable.dart'), args,
        enableAsserts: enableAsserts,
        packagesFile:
            entrypoint.isCached ? _getPackagesFilePath(package) : null,
        // Don't use snapshots for executables activated from paths.
        snapshotPath: entrypoint.isCached
            ? p.join(
                _directory, package, 'bin', '$executable.dart.snapshot.dart2')
            : null,
        recompile: () => _precompileExecutables(entrypoint, package));
  }

  /// Gets the path to the lock file for an activated cached package with
  /// [name].
  String _getLockFilePath(String name) =>
      p.join(_directory, name, 'pubspec.lock');

  /// Gets the path to the .packages file for an activated cached package with
  /// [name].
  String _getPackagesFilePath(String name) =>
      p.join(_directory, name, '.packages');

  /// Gets the path to the `package_config.json` file for an
  /// activated cached package with [name].
  String _getPackageConfigFilePath(String name) =>
      p.join(_directory, name, '.dart_tool', 'package_config.json');

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
    var name = p.basenameWithoutExtension(path);
    if (!fileExists(path)) path = p.join(path, 'pubspec.lock');

    var id =
        LockFile.load(p.join(_directory, path), cache.sources).packages[name];

    if (id == null) {
      throw FormatException("Pubspec for activated package $name didn't "
          'contain an entry for itself.');
    }

    return id;
  }

  /// Returns formatted string representing the package [id].
  String _formatPackage(PackageId id) {
    var source = id.source;
    if (source is GitSource) {
      var url = source.urlFromDescription(id.description);
      return '${log.bold(id.name)} ${id.version} from Git repository "$url"';
    } else if (source is PathSource) {
      var path = source.pathFromDescription(id.description);
      return '${log.bold(id.name)} ${id.version} at path "$path"';
    } else {
      return '${log.bold(id.name)} ${id.version}';
    }
  }

  /// Repairs any corrupted globally-activated packages and their binstubs.
  ///
  /// Returns a pair of two lists of strings. The first indicates which packages
  /// were successfully re-activated; the second indicates which failed.
  Future<Pair<List<String>, List<String>>> repairActivatedPackages() async {
    var executables = <String, List<String>>{};
    if (dirExists(_binStubDir)) {
      for (var entry in listDir(_binStubDir)) {
        try {
          var binstub = readTextFile(entry);
          var package = _binStubProperty(binstub, 'Package');
          if (package == null) {
            throw ApplicationException("No 'Package' property.");
          }

          var executable = _binStubProperty(binstub, 'Executable');
          if (executable == null) {
            throw ApplicationException("No 'Executable' property.");
          }

          executables.putIfAbsent(package, () => []).add(executable);
        } catch (error, stackTrace) {
          log.error(
              'Error reading binstub for '
              '"${p.basenameWithoutExtension(entry)}"',
              error,
              stackTrace);

          tryDeleteEntry(entry);
        }
      }
    }

    var successes = <String>[];
    var failures = <String>[];
    if (dirExists(_directory)) {
      for (var entry in listDir(_directory)) {
        PackageId id;
        try {
          id = _loadPackageId(entry);
          log.message('Reactivating ${log.bold(id.name)} ${id.version}...');

          var entrypoint = find(id.name);
          var snapshots = await _precompileExecutables(entrypoint, id.name);
          var packageExecutables = executables.remove(id.name) ?? [];
          _updateBinStubs(
              entrypoint.packageGraph.packages[id.name], packageExecutables,
              overwriteBinStubs: true,
              snapshots: snapshots,
              suggestIfNotOnPath: false);
          successes.add(id.name);
        } catch (error, stackTrace) {
          var message = 'Failed to reactivate '
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
      var message = StringBuffer('Binstubs exist for non-activated '
          'packages:\n');
      executables.forEach((package, executableNames) {
        for (var executable in executableNames) {
          deleteEntry(p.join(_binStubDir, executable));
        }

        message.writeln('  From ${log.bold(package)}: '
            '${toSentence(executableNames)}');
      });
      log.error(message);
    }

    return Pair(successes, failures);
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
  /// If [overwriteBinStubs] is `true`, any binstubs that collide with
  /// existing binstubs in other packages will be overwritten by this one's.
  /// Otherwise, the previous ones will be preserved.
  ///
  /// If [snapshots] is given, it is a map of the names of executables whose
  /// snapshots were precompiled to the paths of those snapshots. Binstubs for
  /// those will run the snapshot directly and skip pub entirely.
  ///
  /// If [suggestIfNotOnPath] is `true` (the default), this will warn the user if
  /// the bin directory isn't on their path.
  void _updateBinStubs(Package package, List<String> executables,
      {bool overwriteBinStubs,
      Map<String, String> snapshots,
      bool suggestIfNotOnPath = true}) {
    snapshots ??= const {};

    // Remove any previously activated binstubs for this package, in case the
    // list of executables has changed.
    _deleteBinStubs(package.name);

    if ((executables != null && executables.isEmpty) ||
        package.pubspec.executables.isEmpty) {
      return;
    }

    ensureDir(_binStubDir);

    var installed = <String>[];
    var collided = <String, String>{};
    var allExecutables = ordered(package.pubspec.executables.keys);
    for (var executable in allExecutables) {
      if (executables != null && !executables.contains(executable)) continue;

      var script = package.pubspec.executables[executable];

      var previousPackage = _createBinStub(package, executable, script,
          overwrite: overwriteBinStubs, snapshot: snapshots[script]);
      if (previousPackage != null) {
        collided[executable] = previousPackage;

        if (!overwriteBinStubs) continue;
      }

      installed.add(executable);
    }

    if (installed.isNotEmpty) {
      var names = namedSequence('executable', installed.map(log.bold));
      log.message('Installed $names.');
    }

    // Show errors for any collisions.
    if (collided.isNotEmpty) {
      for (var command in ordered(collided.keys)) {
        if (overwriteBinStubs) {
          log.warning('Replaced ${log.bold(command)} previously installed from '
              '${log.bold(collided[command])}.');
        } else {
          log.warning('Executable ${log.bold(command)} was already installed '
              'from ${log.bold(collided[command])}.');
        }
      }

      if (!overwriteBinStubs) {
        log.warning('Deactivate the other package(s) or activate '
            '${log.bold(package.name)} using --overwrite.');
      }
    }

    // Show errors for any unknown executables.
    if (executables != null) {
      var unknown = ordered(executables
          .where((exe) => !package.pubspec.executables.keys.contains(exe)));
      if (unknown.isNotEmpty) {
        dataError("Unknown ${namedSequence('executable', unknown)}.");
      }
    }

    // Show errors for any missing scripts.
    // TODO(rnystrom): This can print false positives since a script may be
    // produced by a transformer. Do something better.
    var binFiles = package
        .listFiles(beneath: 'bin', recursive: false)
        .map((path) => package.relative(path))
        .toList();
    for (var executable in installed) {
      var script = package.pubspec.executables[executable];
      var scriptPath = p.join('bin', '$script.dart');
      if (!binFiles.contains(scriptPath)) {
        log.warning('Warning: Executable "$executable" runs "$scriptPath", '
            'which was not found in ${log.bold(package.name)}.');
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
  /// If [snapshot] is non-null, it is a path to a snapshot file. The binstub
  /// will invoke that directly. Otherwise, it will run `pub global run`.
  ///
  /// If a collision occurs, returns the name of the package that owns the
  /// existing binstub. Otherwise returns `null`.
  String _createBinStub(Package package, String executable, String script,
      {bool overwrite, String snapshot}) {
    var binStubPath = p.join(_binStubDir, executable);
    if (Platform.isWindows) binStubPath += '.bat';

    // See if the binstub already exists. If so, it's for another package
    // since we already deleted all of this package's binstubs.
    String previousPackage;
    if (fileExists(binStubPath)) {
      var contents = readTextFile(binStubPath);
      previousPackage = _binStubProperty(contents, 'Package');
      if (previousPackage == null) {
        log.fine('Could not parse binstub $binStubPath:\n$contents');
      } else if (!overwrite) {
        return previousPackage;
      }
    }

    // If the script was precompiled to a snapshot, just invoke that directly
    // and skip pub global run entirely.
    String invocation;
    if (snapshot != null) {
      // We expect absolute paths from the precompiler since relative ones
      // won't be relative to the right directory when the user runs this.
      assert(p.isAbsolute(snapshot));
      invocation = 'dart "$snapshot"';
    } else {
      invocation = 'pub global run ${package.name}:$script';
    }

    if (Platform.isWindows) {
      var batch = '''
@echo off
rem This file was created by pub v${sdk.version}.
rem Package: ${package.name}
rem Version: ${package.version}
rem Executable: $executable
rem Script: $script
$invocation %*
''';

      if (snapshot != null) {
        batch += '''

rem The VM exits with code 253 if the snapshot version is out-of-date.
rem If it is, we need to delete it and run "pub global" manually.
if not errorlevel 253 (
  exit /b %errorlevel%
)

pub global run ${package.name}:$script %*
''';
      }

      writeTextFile(binStubPath, batch);
    } else {
      var bash = '''
#!/usr/bin/env sh
# This file was created by pub v${sdk.version}.
# Package: ${package.name}
# Version: ${package.version}
# Executable: $executable
# Script: $script
$invocation "\$@"
''';

      if (snapshot != null) {
        bash += '''

# The VM exits with code 253 if the snapshot version is out-of-date.
# If it is, we need to delete it and run "pub global" manually.
exit_code=\$?
if [ \$exit_code != 253 ]; then
  exit \$exit_code
fi

pub global run ${package.name}:$script "\$@"
''';
      }

      // Write this as the system encoding since the system is going to execute
      // it and it might contain non-ASCII characters in the pathnames.
      writeTextFile(binStubPath, bash, encoding: const SystemEncoding());

      // Make it executable.
      var result = Process.runSync('chmod', ['+x', binStubPath]);
      if (result.exitCode != 0) {
        // Couldn't make it executable so don't leave it laying around.
        try {
          deleteEntry(binStubPath);
        } on IOException catch (err) {
          // Do nothing. We're going to fail below anyway.
          log.fine('Could not delete binstub:\n$err');
        }

        fail('Could not make "$binStubPath" executable (exit code '
            '${result.exitCode}):\n${result.stderr}');
      }
    }

    return previousPackage;
  }

  /// Deletes all existing binstubs for [package].
  void _deleteBinStubs(String package) {
    if (!dirExists(_binStubDir)) return;

    for (var file in listDir(_binStubDir, includeDirs: false)) {
      var contents = readTextFile(file);
      var binStubPackage = _binStubProperty(contents, 'Package');
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
      var result = runProcessSync('where', [r'\q', installed + '.bat']);
      if (result.exitCode == 0) return;

      log.warning("${log.yellow('Warning:')} Pub installs executables into "
          '${log.bold(_binStubDir)}, which is not on your path.\n'
          "You can fix that by adding that directory to your system's "
          '"Path" environment variable.\n'
          'A web search for "configure windows path" will show you how.');
    } else {
      // See if the shell can find one of the binstubs.
      //
      // The "command" builtin is more reliable than the "which" executable. See
      // http://unix.stackexchange.com/questions/85249/why-not-use-which-what-to-use-then
      var result =
          runProcessSync('command', ['-v', installed], runInShell: true);
      if (result.exitCode == 0) return;

      var binDir = _binStubDir;
      if (binDir.startsWith(Platform.environment['HOME'])) {
        binDir = p.join(
            r'$HOME', p.relative(binDir, from: Platform.environment['HOME']));
      }

      log.warning("${log.yellow('Warning:')} Pub installs executables into "
          '${log.bold(binDir)}, which is not on your path.\n'
          "You can fix that by adding this to your shell's config file "
          '(.bashrc, .bash_profile, etc.):\n'
          '\n'
          "  ${log.bold('export PATH="\$PATH":"$binDir"')}\n"
          '\n');
    }
  }

  /// Returns the value of the property named [name] in the bin stub script
  /// [source].
  String _binStubProperty(String source, String name) {
    var pattern = RegExp(RegExp.escape(name) + r': ([a-zA-Z0-9_-]+)');
    var match = pattern.firstMatch(source);
    return match == null ? null : match[1];
  }
}
