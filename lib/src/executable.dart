// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:pedantic/pedantic.dart';

import 'entrypoint.dart';
import 'exit_codes.dart' as exit_codes;
import 'io.dart';
import 'isolate.dart' as isolate;
import 'log.dart' as log;
import 'utils.dart';

/// Take a list of experiments to enable and turn them into a list with a single
/// argument to pass to the VM enabling the same experiments.
List<String> vmArgFromExperiments(List<String> experiments) {
  return [
    if (experiments.isNotEmpty) "--enable-experiment=${experiments.join(',')}"
  ];
}

/// Runs [executable] from [package] reachable from [entrypoint].
///
/// The [executable] is a relative path to a Dart file within [package], which
/// should either be the entrypoint package or an immediate dependency of it.
///
/// Arguments from [args] will be passed to the spawned Dart application.
///
/// If [enableAsserts] is true, the program is run with assertions enabled.
///
/// If [packagesFile] is passed, it's used as the package config file path for
/// the executable. Otherwise, `entrypoint.packagesFile` is used.
///
/// If the executable is in an immutable package and we pass no [vmArgs], it
/// run from snapshot (and precompiled if the snapshot doesn't already exist).
///
/// Returns the exit code of the spawned app.
Future<int> runExecutable(
    Entrypoint entrypoint, Executable executable, Iterable<String> args,
    {bool enableAsserts = false,
    String packagesFile,
    Future<void> Function(Executable) recompile,
    List<String> vmArgs = const []}) async {
  final package = executable.package;
  packagesFile ??= entrypoint.packagesFile;

  // Make sure the package is an immediate dependency of the entrypoint or the
  // entrypoint itself.
  if (entrypoint.root.name != executable.package &&
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

  var snapshotPath = entrypoint.snapshotPathOfExecutable(executable);

  // Don't compile snapshots for mutable packages, since their code may
  // change later on.
  //
  // Also we don't snapshot if we have non-default arguments to the VM, as
  // these would be inconsistent if another set of settings are given in a
  // later invocation.
  var useSnapshot =
      !entrypoint.packageGraph.isPackageMutable(package) && vmArgs.isEmpty;

  var executablePath = entrypoint.resolveExecutable(executable);
  if (!fileExists(executablePath)) {
    var message = 'Could not find ${log.bold(executable.relativePath)}';
    if (entrypoint.isGlobal || package != entrypoint.root.name) {
      message += ' in package ${log.bold(package)}';
    }
    log.error('$message.');
    return exit_codes.NO_INPUT;
  }

  if (useSnapshot) {
    // Since we don't access the package graph, this doesn't happen
    // automatically.
    entrypoint.assertUpToDate();

    if (!fileExists(snapshotPath)) {
      await recompile(executable);
    }
    executablePath = snapshotPath;
  } else {
    if (executablePath == null) {
      var message = 'Could not find ${log.bold(executable.relativePath)}';
      if (entrypoint.isGlobal || package != entrypoint.root.name) {
        message += ' in package ${log.bold(package)}';
      }
      log.error('$message.');
      return exit_codes.NO_INPUT;
    }
  }

  // We use an absolute path here not because the VM insists but because it's
  // helpful for the subprocess to be able to spawn Dart with
  // Platform.executableArguments and have that work regardless of the working
  // directory.
  var packageConfig = p.absolute(packagesFile);

  try {
    return _runDartProgram(executablePath, args, packageConfig,
        enableAsserts: enableAsserts, vmArgs: vmArgs);
  } on IsolateSpawnException catch (error) {
    if (!useSnapshot ||
        !error.message.contains('Invalid kernel binary format version')) {
      rethrow;
    }

    log.fine('Precompiled executable is out of date.');
    await recompile(executable);
    return _runDartProgram(executablePath, args, packageConfig,
        enableAsserts: enableAsserts, vmArgs: vmArgs);
  }
}

/// Runs the dart program (can be a snapshot) at [path] with [args] and hooks
/// its stdout, stderr, and sdtin to this process's.
///
/// [packageConfig] is the path to the ".dart_tool/package_config.json" file.
///
/// If [enableAsserts] is set, runs the program with assertions enabled.
///
/// Passes [vmArgs] to the vm.
///
/// Returns the programs's exit code.
Future<int> _runDartProgram(
    String path, List<String> args, String packageConfig,
    {bool enableAsserts, List<String> vmArgs}) async {
  path = p.absolute(path);
  packageConfig = p.absolute(packageConfig);

  // We use Isolate.spawnUri when there are no extra vm-options.
  // That provides better signal handling, and possibly faster startup.
  if (vmArgs.isEmpty) {
    var argList = args.toList();
    await isolate.runUri(p.toUri(path), argList, null,
        enableAsserts: enableAsserts,
        automaticPackageResolution: packageConfig == null,
        packageConfig: p.toUri(packageConfig));
    return exitCode;
  } else {
    // By ignoring sigint, only the child process will get it when
    // they are sent to the current process group. That is what happens when
    // you send signals from the terminal.
    //
    // This allows the child to not be orphaned if it sets up handlers for these
    // signals.
    //
    // We do not drain sighub because it is generally a bad idea to have
    // non-default handling for it.
    //
    // We do not drain sigterm and sigusr1/sigusr2 because it does not seem to
    // work well in manual tests.
    //
    // We do not drain sigquit because dart doesn't support listening to it.
    // https://github.com/dart-lang/sdk/issues/41961 .
    //
    // TODO(sigurdm) To handle signals better we would ideally have `exec`
    // semantics without `fork` for starting the subprocess.
    // https://github.com/dart-lang/sdk/issues/41966.
    unawaited(ProcessSignal.sigint.watch().drain());

    final process = await Process.start(
      Platform.resolvedExecutable,
      [
        '--packages=$packageConfig',
        ...vmArgs,
        if (enableAsserts) '--enable-asserts',
        p.toUri(path).toString(),
        ...args,
      ],
      mode: ProcessStartMode.inheritStdio,
    );

    return process.exitCode;
  }
}

/// An executable in a package
class Executable {
  String package;
  // The relative path to the executable inside the root of [package].
  String relativePath;

  // Adapts the program-name following conventions of dart run
  Executable.adaptProgramName(this.package, String program)
      : relativePath = _adaptProgramToPath(program);

  Executable(this.package, this.relativePath);

  static String _adaptProgramToPath(String program) {
    // If the command has a path separator, then it's a path relative to the
    // root of the package. Otherwise, it's implicitly understood to be in
    // "bin".
    if (p.split(program).length == 1) program = p.join('bin', program);

    // The user may pass in an executable without an extension, but the file
    // to actually execute will always have one.
    if (p.extension(program) != '.dart') program += '.dart';
    return program;
  }
}
