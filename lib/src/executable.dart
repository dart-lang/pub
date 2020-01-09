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

/// Runs [executable] from [package] reachable from [entrypoint].
///
/// The [executable] is a relative path to a Dart file within [package], which
/// should either be the entrypoint package or an immediate dependency of it.
///
/// Arguments from [args] will be passed to the spawned Dart application.
///
/// If [checked] is true, the program is run with assertions enabled.
///
/// If [packagesFile] is passed, it's used as the package config file path for
/// the executable. Otherwise, `entrypoint.packagesFile` is used.
///
/// If [snapshotPath] is passed, this will run the executable from that snapshot
/// if it exists. If [recompile] is passed, it's called if the snapshot is
/// out-of-date or nonexistent. It's expected to regenerate a snapshot at
/// [snapshotPath], after which the snapshot will be re-run. It's ignored if
/// [snapshotPath] isn't passed.
///
/// Returns the exit code of the spawned app.
Future<int> runExecutable(Entrypoint entrypoint, String package,
    String executable, Iterable<String> args,
    {bool checked = false,
    String packagesFile,
    String snapshotPath,
    Future<void> Function() recompile}) async {
  packagesFile ??= entrypoint.packagesFile;

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
  // normal pub output that may be shown when recompiling snapshots if we are
  // not attached to a terminal. This is to not pollute stdout when the output
  // of `pub run` is piped somewhere.
  if (log.verbosity == log.Verbosity.NORMAL && !stdout.hasTerminal) {
    log.verbosity = log.Verbosity.WARNING;
  }

  // Uncached packages are run from source.
  if (snapshotPath != null) {
    // Since we don't access the package graph, this doesn't happen
    // automatically.
    entrypoint.assertUpToDate();

    var result = await _runOrCompileSnapshot(snapshotPath, args,
        packagesFile: packagesFile, checked: checked, recompile: recompile);
    if (result != null) return result;
  }

  // If the command has a path separator, then it's a path relative to the
  // root of the package. Otherwise, it's implicitly understood to be in
  // "bin".
  if (p.split(executable).length == 1) executable = p.join('bin', executable);

  var executablePath = await _executablePath(entrypoint, package, executable);

  if (executablePath == null) {
    var message = 'Could not find ${log.bold(executable)}';
    if (entrypoint.isGlobal || package != entrypoint.root.name) {
      message += ' in package ${log.bold(package)}';
    }
    log.error('$message.');
    return exit_codes.NO_INPUT;
  }

  // We use an absolute path here not because the VM insists but because it's
  // helpful for the subprocess to be able to spawn Dart with
  // Platform.executableArguments and have that work regardless of the working
  // directory.
  var packageConfig = p.toUri(p.absolute(packagesFile));

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
    Entrypoint entrypoint, String package, String path) async {
  assert(p.isRelative(path));

  var fullPath = entrypoint.packageGraph.packages[package].path(path);
  if (!fileExists(fullPath)) return null;
  return p.absolute(fullPath);
}

/// Like [_runSnapshot], but runs [recompile] if [path] doesn't exist yet.
///
/// Returns `null` if [path] doesn't exist and isn't generated by [recompile].
Future<int> _runOrCompileSnapshot(String path, Iterable<String> args,
    {Future<void> Function() recompile,
    String packagesFile,
    bool checked = false}) async {
  if (!fileExists(path)) {
    if (recompile == null) return null;
    await recompile();
    if (!fileExists(path)) return null;
  }

  return await _runSnapshot(path, args,
      recompile: recompile, packagesFile: packagesFile, checked: checked);
}

/// Runs the snapshot at [path] with [args] and hooks its stdout, stderr, and
/// sdtin to this process's.
///
/// If [recompile] is passed, it's called if the snapshot is out-of-date. It's
/// expected to regenerate a snapshot at [path], after which the snapshot will
/// be re-run.
///
/// If [checked] is set, runs the snapshot with assertions enabled.
///
/// Returns the snapshot's exit code.
///
/// This doesn't do any validation of the snapshot's SDK version.
Future<int> _runSnapshot(String path, Iterable<String> args,
    {Future<void> Function() recompile,
    String packagesFile,
    bool checked = false}) async {
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
    if (!error.message.contains('Invalid kernel binary format version')) {
      rethrow;
    }

    log.fine('Precompiled executable is out of date.');
    await recompile();
    await isolate.runUri(url, argList, null,
        checked: checked, packageConfig: packageConfig);
  }

  return exitCode;
}
