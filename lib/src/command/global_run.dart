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

/// Handles the `global run` pub command.
class GlobalRunCommand extends PubCommand {
  @override
  String get name => 'run';
  @override
  String get description =>
      'Run an executable from a globally activated package.\n'
      "NOTE: We are currently optimizing this command's startup time.";
  @override
  String get invocation => 'pub global run <package>:<executable> [args...]';
  @override
  bool get allowTrailingOptions => false;

  GlobalRunCommand() {
    argParser.addFlag('enable-asserts', help: 'Enable assert statements.');
    argParser.addFlag('checked', abbr: 'c', hide: true);
    argParser.addMultiOption('enable-experiment',
        help: 'Runs the executable in a VM with the given experiments enabled.',
        valueHelp: 'experiment');
    argParser.addOption('mode', help: 'Deprecated option', hide: true);
  }

  @override
  Future run() async {
    if (argResults.rest.isEmpty) {
      usageException('Must specify an executable to run.');
    }

    String package;
    var executable = argResults.rest[0];
    if (executable.contains(':')) {
      var parts = split1(executable, ':');
      package = parts[0];
      executable = parts[1];
    } else {
      // If the package name is omitted, use the same name for both.
      package = executable;
    }

    var args = argResults.rest.skip(1).toList();
    if (p.split(executable).length > 1) {
      usageException('Cannot run an executable in a subdirectory of a global '
          'package.');
    }

    if (argResults.wasParsed('mode')) {
      log.warning('The --mode flag is deprecated and has no effect.');
    }

    final experiments = argResults['enable-experiment'] as List;
    final vmArgs = <String>[
      if (experiments.isNotEmpty) "--enable_experiment=${experiments.join(',')}"
    ];
    final globalEntrypoint = await globals.find(package);
    final exitCode = await runExecutable(
        globalEntrypoint, Executable(package, executable), args,
        vmArgs: vmArgs,
        enableAsserts: argResults['enable-asserts'] || argResults['checked'],
        recompile: globalEntrypoint.precompileExecutable);
    await flushThenExit(exitCode);
  }
}
