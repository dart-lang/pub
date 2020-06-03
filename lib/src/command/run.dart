// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:path/path.dart' as p;

import '../command.dart';
import '../executable.dart';
import '../io.dart';
import '../log.dart' as log;
import '../utils.dart';

/// Handles the `run` pub command.
class RunCommand extends PubCommand {
  @override
  String get name => 'run';
  @override
  String get description => 'Run an executable from a package.';
  @override
  String get invocation => 'pub run <executable> [args...]';
  @override
  String get docUrl => 'https://dart.dev/tools/pub/cmd/pub-run';
  @override
  bool get allowTrailingOptions => false;

  RunCommand() {
    argParser.addFlag('enable-asserts', help: 'Enable assert statements.');
    argParser.addFlag('checked', abbr: 'c', hide: true);
    argParser.addMultiOption('enable-experiment',
        help:
            'Runs the executable in a VM with the given experiments enabled.\n'
            '(Will disable snapshotting, resulting in slower startup)',
        valueHelp: 'experiment');
    argParser.addOption('mode', help: 'Deprecated option', hide: true);
    // mode exposed for `dartdev run` to use as subprocess.
    argParser.addFlag('dart-dev-run', hide: true);
  }

  @override
  Future run() async {
    if (argResults['dart-dev-run']) {
      return await _runFromDartDev();
    }
    if (argResults.rest.isEmpty) {
      usageException('Must specify an executable to run.');
    }

    var package = entrypoint.root.name;
    var executable = argResults.rest[0];
    var args = argResults.rest.skip(1).toList();

    // A command like "foo:bar" runs the "bar" script from the "foo" package.
    // If there is no colon prefix, default to the root package.
    if (executable.contains(':')) {
      var components = split1(executable, ':');
      package = components[0];
      executable = components[1];

      if (p.split(executable).length > 1) {
        usageException(
            'Cannot run an executable in a subdirectory of a dependency.');
      }
    } else if (onlyIdentifierRegExp.hasMatch(executable)) {
      // "pub run foo" means the same thing as "pub run foo:foo" as long as
      // "foo" is a valid Dart identifier (and thus package name).
      package = executable;
    }

    if (argResults.wasParsed('mode')) {
      log.warning('The --mode flag is deprecated and has no effect.');
    }

    final experiments = argResults['enable-experiment'] as List;
    final vmArgs = vmArgFromExperiments(experiments);

    var exitCode = await runExecutable(
        entrypoint, Executable.adaptProgramName(package, executable), args,
        enableAsserts: argResults['enable-asserts'] || argResults['checked'],
        recompile: entrypoint.precompileExecutable,
        vmArgs: vmArgs);
    await flushThenExit(exitCode);
  }

  /// Implement a mode for use in `dartdev run`.
  ///
  /// Usage: `dartdev run [package[:command]]`
  ///
  /// If `package` is not given, defaults to current root package.
  /// If `command` is not given, defaults to name of `package`.
  ///
  /// Runs `bin/<command>.dart` from package `<package>`. If `<package>` is not
  /// mutable (local root package or path-dependency) a source snapshot will be
  /// cached in
  /// `.dart_tool/pub/bin/<package>/<command>.dart-<sdkVersion>.snapshot`.
  Future _runFromDartDev() async {
    var package = entrypoint.root.name;
    var command = package;
    var args = <String>[];

    if (argResults.rest.isNotEmpty) {
      if (argResults.rest[0].contains(RegExp(r'[/\\]'))) {
        usageException('[<package>[:command]] cannot contain "/" or "\\"');
      }

      package = argResults.rest[0];
      if (package.contains(':')) {
        final parts = package.split(':');
        if (parts.length > 2) {
          usageException('[<package>[:command]] cannot contain multiple ":"');
        }
        package = parts[0];
        command = parts[1];
      } else {
        command = package;
      }
      args = argResults.rest.skip(1).toList();
    }

    final experiments = argResults['enable-experiment'] as List;
    final vmArgs = vmArgFromExperiments(experiments);

    return await flushThenExit(await runExecutable(
        entrypoint, Executable(package, 'bin/$command.dart'), args,
        vmArgs: vmArgs,
        enableAsserts: argResults['enable-asserts'] || argResults['checked'],
        recompile: entrypoint.precompileExecutable));
  }
}
