// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:async/async.dart';
import 'package:barback/barback.dart';
import 'package:path/path.dart' as p;

import 'barback/asset_environment.dart';
import 'entrypoint.dart';
import 'exit_codes.dart' as exit_codes;
import 'io.dart';
import 'log.dart' as log;
import 'utils.dart';

/// All signals that can be caught by a Dart process.
///
/// This intentionally omits SIGINT. SIGINT usually comes from a user pressing
/// Control+C on the terminal, and the terminal automatically passes the signal
/// to all processes in the process tree. If we forwarded it manually, the
/// subprocess would see two instances, which could cause problems. Instead, we
/// just ignore it and let the terminal pass it to the subprocess.
final _catchableSignals = Platform.isWindows
    ? [ProcessSignal.SIGHUP]
    : [
        ProcessSignal.SIGHUP,
        ProcessSignal.SIGTERM,
        ProcessSignal.SIGUSR1,
        ProcessSignal.SIGUSR2,
        ProcessSignal.SIGWINCH,
      ];

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
    String executable, Iterable<String> args, {bool isGlobal: false,
    bool checked: false, BarbackMode mode}) async {
  if (mode == null) mode = BarbackMode.RELEASE;

  // Make sure the package is an immediate dependency of the entrypoint or the
  // entrypoint itself.
  if (entrypoint.root.name != package &&
      !entrypoint.root.immediateDependencies
          .any((dep) => dep.name == package)) {
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

  var localSnapshotPath = p.join(".pub", "bin", package,
      "$executable.snapshot");
  if (!isGlobal && fileExists(localSnapshotPath) &&
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

  var vmArgs = <String>[];

  // Run in checked mode.
  if (checked) vmArgs.add("--checked");

  var executableUrl = await _executableUrl(
      entrypoint, package, executable, isGlobal: isGlobal, mode: mode);

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
  // example, it may not have the right packages directory itself.
  //
  // We don't do this for global executables because older ones may not have a
  // `.packages` file generated. If they do, the VM's logic will find it
  // automatically.
  if (!isGlobal &&
      (executableUrl.scheme == 'file' || executableUrl.scheme == '')) {
    // We use an absolute path here not because the VM insists but because it's
    // helpful for the subprocess to be able to spawn Dart with
    // Platform.executableArguments and have that work regardless of the working
    // directory.
    vmArgs.add('--packages=${p.toUri(p.absolute(entrypoint.packagesFile))}');
  }

  vmArgs.add(executableUrl.toString());
  vmArgs.addAll(args);

  var process = await Process.start(Platform.executable, vmArgs);

  _forwardSignals(process);

  // Note: we're not using process.std___.pipe(std___) here because
  // that prevents pub from also writing to the output streams.
  process.stderr.listen(stderr.add);
  process.stdout.listen(stdout.add);
  stdin.listen(process.stdin.add, onDone: process.stdin.close);

  // Work around dart-lang/sdk#25348.
  process.stdin.done.catchError((_) {});

  return await process.exitCode;
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
  //
  // TODO(nweiz): Once sdk#23369 is fixed, allow global executables to be run
  // (and snapshotted) from the filesystem using package specs. A spec can by
  // saved when activating the package.
  if (!isGlobal && !entrypoint.packageGraph.isPackageTransformed(package)) {
    var fullPath = entrypoint.packageGraph.packages[package].path(path);
    if (!fileExists(fullPath)) return null;
    return p.toUri(fullPath);
  }

  var assetPath = p.url.joinAll(p.split(path));
  var id = new AssetId(package, assetPath);

  // TODO(nweiz): Use [packages] to only load assets from packages that the
  // executable might load.
  var environment = await AssetEnvironment.create(entrypoint, mode,
      useDart2JS: false, entrypoints: [id]);
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
  var relativePath = p.url.relative(assetPath,
      from: p.url.joinAll(p.split(server.rootDirectory)));
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
Future<int> runSnapshot(String path, Iterable<String> args, {recompile(),
    String packagesFile, bool checked: false}) async {
  // TODO(nweiz): pass a flag to silence the "Wrong full snapshot version"
  // message when issue 20784 is fixed.
  var vmArgs = <String>[];
  if (checked) vmArgs.add("--checked");

  if (packagesFile != null) {
    // We use an absolute path here not because the VM insists but because it's
    // helpful for the subprocess to be able to spawn Dart with
    // Platform.executableArguments and have that work regardless of the working
    // directory.
    vmArgs.add("--packages=${p.toUri(p.absolute(packagesFile))}");
  }

  vmArgs.add(path);
  vmArgs.addAll(args);

  // We need to split stdin so that we can send the same input both to the
  // first and second process, if we start more than one.
  var stdin1;
  var stdin2;
  if (recompile == null) {
    stdin1 = stdin;
  } else {
    var stdins = StreamSplitter.splitFrom(stdin);
    stdin1 = stdins.first;
    stdin2 = stdins.last;
  }

  runProcess(input) async {
    var process = await Process.start(Platform.executable, vmArgs);

    _forwardSignals(process);

    // Note: we're not using process.std___.pipe(std___) here because
    // that prevents pub from also writing to the output streams.
    process.stderr.listen(stderr.add);
    process.stdout.listen(stdout.add);
    input.listen(process.stdin.add);

    return process.exitCode;
  }

  var exitCode = await runProcess(stdin1);
  if (recompile == null || exitCode != 253) return exitCode;

  // Exit code 253 indicates that the snapshot version was out-of-date. If we
  // can recompile, do so.
  await recompile();
  return runProcess(stdin2);
}

/// Forwards all catchable signals to [process].
void _forwardSignals(Process process) {
  // See [_catchableSignals].
  ProcessSignal.SIGINT.watch().listen(
      (_) => log.fine("Ignoring SIGINT in pub."));

  for (var signal in _catchableSignals) {
    signal.watch().listen((_) {
      log.fine("Forwarding $signal to running process.");
      process.kill(signal);
    });
  }
}

/// Runs the executable snapshot at [snapshotPath].
Future<int> _runCachedExecutable(Entrypoint entrypoint, String snapshotPath,
    List<String> args, {bool checked: false}) {
  return runSnapshot(snapshotPath, args,
      packagesFile: entrypoint.packagesFile,
      checked: checked,
      recompile: () {
    log.fine("Precompiled executable is out of date.");
    return entrypoint.precompileExecutables();
  });
}
