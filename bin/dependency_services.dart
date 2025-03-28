// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Support for automated upgrades.
///
/// For now this is not a finalized interface. Don't rely on this.
library;

import 'dart:async';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:pub/src/command.dart';
import 'package:pub/src/command/dependency_services.dart';
import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:pub/src/io.dart';
import 'package:pub/src/log.dart' as log;
import 'package:pub/src/utils.dart';

class _DependencyServicesCommandRunner extends CommandRunner<int>
    implements PubTopLevel {
  @override
  String get directory => argResults.optionWithDefault('directory');

  @override
  bool get captureStackChains => argResults.flag('verbose');

  @override
  bool get trace => argResults.flag('verbose');

  ArgResults? _argResults;

  /// The top-level options parsed by the command runner.
  @override
  ArgResults get argResults {
    final a = _argResults;
    if (a == null) {
      throw StateError(
        'argResults cannot be used before Command.run is called.',
      );
    }
    return a;
  }

  _DependencyServicesCommandRunner()
    : super(
        'dependency_services',
        'Support for automatic upgrades',
        usageLineLength: lineLength,
      ) {
    argParser.addFlag(
      'verbose',
      abbr: 'v',
      negatable: false,
      help: 'Shortcut for "--verbosity=all".',
    );
    PubTopLevel.addColorFlag(argParser);
    argParser.addOption(
      'directory',
      abbr: 'C',
      help: 'Run the subcommand in the directory<dir>.',
      defaultsTo: '.',
      valueHelp: 'dir',
    );

    addCommand(DependencyServicesListCommand());
    addCommand(DependencyServicesReportCommand());
    addCommand(DependencyServicesApplyCommand());
  }

  @override
  Future<int> run(Iterable<String> args) async {
    try {
      _argResults = parse(args);
      return await runCommand(argResults) ?? exit_codes.SUCCESS;
    } on UsageException catch (error) {
      log.exception(error);
      return exit_codes.USAGE;
    }
  }

  @override
  void printUsage() {
    log.message(usage);
  }

  @override
  log.Verbosity get verbosity => log.Verbosity.normal;
}

Future<void> main(List<String> arguments) async {
  await flushThenExit(await _DependencyServicesCommandRunner().run(arguments));
}
