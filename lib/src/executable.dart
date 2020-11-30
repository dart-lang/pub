// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:args/args.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import 'entrypoint.dart';
import 'exceptions.dart';
import 'exit_codes.dart' as exit_codes;
import 'io.dart';
import 'isolate.dart' as isolate;
import 'log.dart' as log;
import 'log.dart';
import 'solver/type.dart';
import 'system_cache.dart';
import 'utils.dart';

/// Code shared between `run` `global run` and `run --dartdev` for extracting
/// vm arguments from arguments.
List<String> vmArgsFromArgResults(ArgResults argResults) {
  final experiments = argResults['enable-experiment'] as List;
  return [
    if (experiments.isNotEmpty) "--enable-experiment=${experiments.join(',')}",
    if (argResults.wasParsed('sound-null-safety'))
      argResults['sound-null-safety']
          ? '--sound-null-safety'
          : '--no-sound-null-safety',
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
/// If the executable is in an immutable package and we pass no [vmArgs], it
/// run from snapshot (and precompiled if the snapshot doesn't already exist).
///
/// Returns the exit code of the spawned app.
Future<int> runExecutable(
    Entrypoint entrypoint, Executable executable, Iterable<String> args,
    {bool enableAsserts = false,
    Future<void> Function(Executable) recompile,
    List<String> vmArgs = const [],
    @required bool alwaysUseSubprocess}) async {
  final package = executable.package;

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
    var message =
        'Could not find ${log.bold(p.normalize(executable.relativePath))}';
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
      var message =
          'Could not find ${log.bold(p.normalize(executable.relativePath))}';
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
  final packageConfigAbsolute = p.absolute(entrypoint.packageConfigFile);

  try {
    return await _runDartProgram(
      executablePath,
      args,
      packageConfigAbsolute,
      enableAsserts: enableAsserts,
      vmArgs: vmArgs,
      alwaysUseSubprocess: alwaysUseSubprocess,
    );
  } on IsolateSpawnException catch (error) {
    if (!useSnapshot ||
        !error.message.contains('Invalid kernel binary format version')) {
      rethrow;
    }

    log.fine('Precompiled executable is out of date.');
    await recompile(executable);
    return await _runDartProgram(
      executablePath,
      args,
      packageConfigAbsolute,
      enableAsserts: enableAsserts,
      vmArgs: vmArgs,
      alwaysUseSubprocess: alwaysUseSubprocess,
    );
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
///
/// Tries to run the program as an isolate if no special [vmArgs] are given
/// otherwise starts new vm in a subprocess. If [alwaysUseSubprocess] is `true`
/// a new process will always be started.
Future<int> _runDartProgram(
    String path, List<String> args, String packageConfig,
    {bool enableAsserts,
    List<String> vmArgs,
    @required bool alwaysUseSubprocess}) async {
  path = p.absolute(path);
  packageConfig = p.absolute(packageConfig);

  // We use Isolate.spawnUri when there are no extra vm-options.
  // That provides better signal handling, and possibly faster startup.
  if ((!alwaysUseSubprocess) && vmArgs.isEmpty) {
    var argList = args.toList();
    return await isolate.runUri(p.toUri(path), argList, null,
        enableAsserts: enableAsserts,
        automaticPackageResolution: packageConfig == null,
        packageConfig: p.toUri(packageConfig));
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
    final subscription = ProcessSignal.sigint.watch().listen((e) {});
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

    final exitCode = await process.exitCode;
    await subscription.cancel();
    return exitCode;
  }
}

/// Returns the path to dart program/snapshot to invoke for running [descriptor]
/// resolved according to the package configuration of the package at [root]
/// (defaulting to the current working directory). Using the pub-cache at
/// [pubCacheDir] (defaulting to the default pub cache).
///
/// The returned path will be relative to [root].
///
/// ## Resolution:
///
/// [descriptor] is resolved as follows:
/// * If `<descriptor>` is an existing file (resolved relative to root, either
///   as a path or a file uri):
///   return that (without snapshotting).
///
/// * Otherwise if [root] contains no `pubspec.yaml`, throws a
///  [CommandResolutionFailedException].
///
/// * Otherwise if the current package resolution is outdated do an implicit
/// `pub get`, if that fails, throw a [CommandResolutionFailedException].
///
/// * Otherwise let  `<current>` be the name of the package at [root], and
///   interpret [descriptor] as `[<package>][:<command>]`.
///
///   * If `<package>` is empty: default to the package at [root].
///   * If `<command>` is empty, resolve it as `bin/<package>.dart` or
///     `bin/main.dart` to the first that exists.
///
/// For example:
/// * `foo` will resolve to `foo:bin/foo.dart` or `foo:bin/main.dart`.
/// * `:foo` will resolve to `<current>:bin/foo.dart`.
/// * `` and `:` both resolves to `<current>:bin/<current>.dart` or
///   `bin/<current>:main.dart`.
///
/// If that doesn't resolve as an existing file throw an exception.
///
/// ## Snapshotting
///
/// The returned executable will be a snapshot if [allowSnapshot] is true and
/// the package is an immutable (non-path) dependency of [root].
///
/// If returning the path to a snapshot that doesn't already exist, the script
/// Will be precompiled. And a message will be printed only if a terminal is
/// attached to stdout.
///
/// Throws an [CommandResolutionFailedException] if the command is not found or
/// if the entrypoint is not up to date (requires `pub get`) and a `pub get`.
Future<String> getExecutableForCommand(
  String descriptor, {
  bool allowSnapshot = true,
  String root,
  String pubCacheDir,
}) async {
  root ??= p.current;
  var asPath = descriptor;
  try {
    asPath = Uri.parse(descriptor).toFilePath();
  } catch (_) {
    // Consume input path will either be a valid path or a file uri
    // (e.g /directory/file.dart or file:///directory/file.dart). We will try
    // parsing it as a Uri, but if parsing failed for any reason (likely
    // because path is not a file Uri), `path` will be passed without
    // modification to the VM.
  }

  final asDirectFile = p.join(root, asPath);
  if (fileExists(asDirectFile)) return p.relative(asDirectFile, from: root);
  if (!fileExists(p.join(root, 'pubspec.yaml'))) {
    throw CommandResolutionFailedException('Could not find file `$descriptor`');
  }
  try {
    final entrypoint = Entrypoint(root, SystemCache(rootDir: pubCacheDir));
    try {
      // TODO(sigurdm): it would be nicer with a 'isUpToDate' function.
      entrypoint.assertUpToDate();
    } on DataException {
      await warningsOnlyUnlessTerminal(
          () => entrypoint.acquireDependencies(SolveType.GET));
    }

    String command;
    String package;
    if (descriptor.contains(':')) {
      final parts = descriptor.split(':');
      if (parts.length > 2) {
        throw CommandResolutionFailedException(
            '[<package>[:command]] cannot contain multiple ":"');
      }
      package = parts[0];
      if (package.isEmpty) package = entrypoint.root.name;
      command = parts[1];
    } else {
      package = descriptor;
      if (package.isEmpty) package = entrypoint.root.name;
      command = package;
    }

    final executable = Executable(package, p.join('bin', '$command.dart'));
    if (!entrypoint.packageGraph.packages.containsKey(package)) {
      throw CommandResolutionFailedException(
          'Could not find package `$package` or file `$descriptor`');
    }
    final path = entrypoint.resolveExecutable(executable);
    if (!fileExists(path)) {
      throw CommandResolutionFailedException(
          'Could not find `bin${p.separator}$command.dart` in package `$package`.');
    }
    if (!allowSnapshot || entrypoint.packageGraph.isPackageMutable(package)) {
      return p.relative(path, from: root);
    } else {
      final snapshotPath = entrypoint.snapshotPathOfExecutable(executable);
      if (!fileExists(snapshotPath)) {
        await warningsOnlyUnlessTerminal(
          () => entrypoint.precompileExecutable(executable),
        );
      }
      return p.relative(snapshotPath, from: root);
    }
  } on ApplicationException catch (e) {
    throw CommandResolutionFailedException(e.message);
  }
}

class CommandResolutionFailedException implements Exception {
  final String message;
  CommandResolutionFailedException(this.message);

  @override
  String toString() {
    return 'CommandResolutionFailedException: $message';
  }
}

/// An executable in a package
class Executable {
  String package;

  /// The relative path to the executable inside the root of [package].
  String relativePath;

  /// Adapts the program-name following conventions of dart run
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
