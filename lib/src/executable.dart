// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import 'entrypoint.dart';
import 'exit_codes.dart' as exit_codes;
import 'io.dart';
import 'isolate.dart' as isolate;
import 'log.dart' as log;
import 'utils.dart';
import 'system_cache.dart';

/// Runs [executable] from [package] reachable from [entrypoint].
///
/// The executable string is a relative Dart file path using native path
/// separators with or without a trailing ".dart" extension. It is contained
/// within [package], which should either be the entrypoint package or an
/// immediate dependency of it.
///
/// Arguments from [args] will be passed to the spawned Dart application.
///
/// If [checked] is true, the program is run in checked mode. If [mode] is
/// passed, it's used as the barback mode; it defaults to [BarbackMode.RELEASE].
///
/// Returns the exit code of the spawned app.
Future<int> runExecutable(Entrypoint entrypoint, String package,
    String executable, Iterable<String> args,
    {bool isGlobal: false, bool checked: false, SystemCache cache}) async {
  assert(!isGlobal || cache != null);
  // Make sure the package is an immediate dependency of the entrypoint or the
  // entrypoint itself.
  if (entrypoint.root.name != package &&
      !entrypoint.root.immediateDependencies.containsKey(package)) {
    if (entrypoint.packageGraph.packages.containsKey(package)) {
      dataError('Package "$package" is not an immediate dependency.\n'
          'Cannot run executables in transitive dependencies.');
    } else {
      dataError('Could not find package "$package". Did you forget to add a '
          'dependency?');
    }
  }

  entrypoint.migrateCache();

  // Unless the user overrides the verbosity, we want to filter out the
  // normal pub output shown while loading the environment.
  if (log.verbosity == log.Verbosity.NORMAL) {
    log.verbosity = log.Verbosity.WARNING;
  }

  // Ensure that there's a trailing extension.
  if (p.extension(executable) != ".dart") executable += ".dart";

  var localSnapshotPath =
      p.join(entrypoint.cachePath, "bin", package, "$executable.snapshot");
  if (!isGlobal && fileExists(localSnapshotPath)) {
    // Since we don't access the package graph, this doesn't happen
    // automatically.
    entrypoint.assertUpToDate();

    return _runCachedExecutable(entrypoint, localSnapshotPath, args,
        checked: checked);
  }

  // If the command has a path separator, then it's a path relative to the
  // root of the package. Otherwise, it's implicitly understood to be in
  // "bin".
  if (p.split(executable).length == 1) executable = p.join("bin", executable);

  var executablePath = await _executablePath(entrypoint, package, executable,
      isGlobal: isGlobal, cache: cache);

  if (executablePath == null) {
    var message = "Could not find ${log.bold(executable)}";
    if (isGlobal || package != entrypoint.root.name) {
      message += " in package ${log.bold(package)}";
    }
    log.error("$message.");
    return exit_codes.NO_INPUT;
  }

  // We use an absolute path here not because the VM insists but because it's
  // helpful for the subprocess to be able to spawn Dart with
  // Platform.executableArguments and have that work regardless of the working
  // directory.
  Uri packageConfig = p.toUri(p.absolute(entrypoint.packagesFile));

  await isolate.runUri(p.toUri(executablePath), args.toList(), null,
      checked: checked,
      automaticPackageResolution: packageConfig == null,
      packageConfig: packageConfig);
  return exitCode;
}

/// Returns the full path the VM should use to load the executable at [path].
///
/// [path] must be relative to the root of [package]. If [path] doesn't exist,
/// returns `null`. If the executable is global and doesn't already have a
/// `.packages` file one will be created.
Future<String> _executablePath(
    Entrypoint entrypoint, String package, String path,
    {bool isGlobal: false, SystemCache cache}) async {
  assert(p.isRelative(path));

  if (!fileExists(entrypoint.packagesFile)) {
    if (!isGlobal) return null;
    await writeTextFile(
        entrypoint.packagesFile, entrypoint.lockFile.packagesFile(cache));
  }
  var fullPath = entrypoint.packageGraph.packages[package].path(path);
  if (!fileExists(fullPath)) return null;
  return p.absolute(fullPath);
}

/// Runs the snapshot at [path] with [args] and hooks its stdout, stderr, and
/// sdtin to this process's.
///
/// If [recompile] is passed, it's called if the snapshot is out-of-date. It's
/// expected to regenerate a snapshot at [path], after which the snapshot will
/// be re-run. It may return a Future.
///
/// If [checked] is set, runs the snapshot in checked mode.
///
/// Returns the snapshot's exit code.
///
/// This doesn't do any validation of the snapshot's SDK version.
Future<int> runSnapshot(String path, Iterable<String> args,
    {recompile(), String packagesFile, bool checked: false}) async {
  Uri packageConfig;
  if (packagesFile != null) {
    // We use an absolute path here not because the VM insists but because it's
    // helpful for the subprocess to be able to spawn Dart with
    // Platform.executableArguments and have that work regardless of the working
    // directory.
    packageConfig = p.toUri(p.absolute(packagesFile));
  }

  var url = p.toUri(p.absolute(path));
  var argList = args.toList();
  try {
    await isolate.runUri(url, argList, null,
        checked: checked,
        automaticPackageResolution: packageConfig == null,
        packageConfig: packageConfig);
  } on IsolateSpawnException catch (error) {
    if (recompile == null) rethrow;
    if (!error.message.contains("Wrong script snapshot version")) rethrow;
    await recompile();
    await isolate.runUri(url, argList, null,
        checked: checked, packageConfig: packageConfig);
  }

  return exitCode;
}

/// Runs the executable snapshot at [snapshotPath].
Future<int> _runCachedExecutable(
    Entrypoint entrypoint, String snapshotPath, List<String> args,
    {bool checked: false}) {
  return runSnapshot(snapshotPath, args,
      packagesFile: entrypoint.packagesFile, checked: checked, recompile: () {
    log.fine("Precompiled executable is out of date.");
    return entrypoint.precompileExecutables();
  });
}
