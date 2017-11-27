// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:barback/barback.dart';
import 'package:path/path.dart' as p;

import 'barback/asset_environment.dart';
import 'compiler.dart';
import 'entrypoint.dart';
import 'exit_codes.dart' as exit_codes;
import 'io.dart';
import 'isolate.dart' as isolate;
import 'log.dart' as log;
import 'utils.dart';

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
    {bool isGlobal: false, bool checked: false, BarbackMode mode}) async {
  if (mode == null) mode = BarbackMode.RELEASE;

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

  // Unless the user overrides the verbosity, we want to filter out the
  // normal pub output shown while loading the environment.
  if (log.verbosity == log.Verbosity.NORMAL) {
    log.verbosity = log.Verbosity.WARNING;
  }

  // Ensure that there's a trailing extension.
  if (p.extension(executable) != ".dart") executable += ".dart";

  var localSnapshotPath =
      p.join(".pub", "bin", package, "$executable.snapshot");
  if (!isGlobal &&
      fileExists(localSnapshotPath) &&
      // Dependencies are only snapshotted in release mode, since that's the
      // default mode for them to run. We can't run them in a different mode
      // using the snapshot.
      mode == BarbackMode.RELEASE) {
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

  var executableUrl = await _executableUrl(entrypoint, package, executable,
      isGlobal: isGlobal, mode: mode);

  if (executableUrl == null) {
    var message = "Could not find ${log.bold(executable)}";
    if (isGlobal || package != entrypoint.root.name) {
      message += " in package ${log.bold(package)}";
    }
    log.error("$message.");
    return exit_codes.NO_INPUT;
  }

  // If we're running an executable directly from the filesystem, make sure that
  // it knows where to load the packages. If it's a dependency's executable, for
  // example, it may not have the right packages directory itself. Otherwise,
  // default to Dart's automatic package: logic.
  Uri packageConfig;
  if (executableUrl.scheme == 'file' || executableUrl.scheme == '') {
    // We use an absolute path here not because the VM insists but because it's
    // helpful for the subprocess to be able to spawn Dart with
    // Platform.executableArguments and have that work regardless of the working
    // directory.
    packageConfig = p.toUri(p.absolute(entrypoint.packagesFile));
  }

  await isolate.runUri(executableUrl, args.toList(), null,
      buffered: executableUrl.scheme == 'http',
      checked: checked,
      automaticPackageResolution: packageConfig == null,
      packageConfig: packageConfig);
  return exitCode;
}

/// Returns the URL the VM should use to load the executable at [path].
///
/// [path] must be relative to the root of [package]. If [path] doesn't exist,
/// returns `null`.
Future<Uri> _executableUrl(Entrypoint entrypoint, String package, String path,
    {bool isGlobal: false, BarbackMode mode}) async {
  assert(p.isRelative(path));

  // If neither the executable nor any of its dependencies are transformed,
  // there's no need to spin up a barback server. Just run the VM directly
  // against the filesystem.
  if (!entrypoint.packageGraph.isPackageTransformed(package) &&
      fileExists(entrypoint.packagesFile)) {
    var fullPath = entrypoint.packageGraph.packages[package].path(path);
    if (!fileExists(fullPath)) return null;
    return p.toUri(p.absolute(fullPath));
  }

  var assetPath = p.url.joinAll(p.split(path));
  var id = new AssetId(package, assetPath);

  // TODO(nweiz): Use [packages] to only load assets from packages that the
  // executable might load.
  var environment = await AssetEnvironment
      .create(entrypoint, mode, compiler: Compiler.none, entrypoints: [id]);
  environment.barback.errors.listen((error) {
    log.error(log.red("Build error:\n$error"));
  });

  var server;
  if (package == entrypoint.root.name) {
    // Serve the entire root-most directory containing the entrypoint. That
    // ensures that, for example, things like `import '../../utils.dart';`
    // will work from within some deeply nested script.
    server = await environment.serveDirectory(p.split(path).first);
  } else {
    assert(p.split(path).first == "bin");

    // For other packages, always use the "bin" directory.
    server = await environment.servePackageBinDirectory(package);
  }

  try {
    await environment.barback.getAssetById(id);
  } on AssetNotFoundException catch (_) {
    return null;
  }

  // Get the URL of the executable, relative to the server's root directory.
  var relativePath = p.url
      .relative(assetPath, from: p.url.joinAll(p.split(server.rootDirectory)));
  return server.url.resolve(relativePath);
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
