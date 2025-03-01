// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A trivial embedding of the pub command. Used from tests.
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:pub/pub.dart';
import 'package:pub/src/command.dart';
import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:pub/src/log.dart' as log;

/// A command for explicitly throwing an exception, to test the handling of
/// unexpected exceptions.
class ThrowingCommand extends PubCommand {
  @override
  String get name => 'fail';

  @override
  String get description => 'Throws an exception';

  @override
  Future<int> runProtected() async {
    throw StateError('Pub has crashed');
  }
}

/// A command for testing the [getExecutableForCommand] functionality.
class GetExecutableForCommandCommand extends PubCommand {
  @override
  String get name => 'get-executable-for-command';

  @override
  String get description =>
      'Finds the package config and executable given a command';

  @override
  bool get hidden => true;

  GetExecutableForCommandCommand() {
    argParser.addFlag('allow-snapshot');
  }

  @override
  Future<void> runProtected() async {
    try {
      final result = await getExecutableForCommand(
        argResults.rest[0],
        allowSnapshot: argResults.flag('allow-snapshot'),
      );
      log.message('Executable: ${result.executable}');
      log.message(
        'Package config: ${result.packageConfig ?? 'No package config'}',
      );
    } on CommandResolutionFailedException catch (e) {
      log.message('Error: ${e.message}');
      log.message('Issue: ${e.issue}');
      overrideExitCode(-1);
    }
  }
}

/// A command for testing the [ensurePubspecResolved] functionality.
class EnsurePubspecResolvedCommand extends PubCommand {
  @override
  String get name => 'ensure-pubspec-resolved';

  @override
  String get description => 'Resolves pubspec.yaml if needed';

  @override
  bool get hidden => true;

  @override
  Future<int> runProtected() async {
    await ensurePubspecResolved('.');
    return 0;
  }
}

class RunCommand extends Command<int> {
  @override
  String get name => 'run';

  @override
  String get description => 'runs a dart app';

  @override
  Future<int> run() async {
    final DartExecutableWithPackageConfig executable;
    try {
      executable = await getExecutableForCommand(argResults!.rest.first);
    } on CommandResolutionFailedException catch (e) {
      log.error(e.message);
      return -1;
    }
    final packageConfig = executable.packageConfig;
    final process = await Process.start(Platform.executable, [
      if (packageConfig != null) '--packages=$packageConfig',
      executable.executable,
      ...argResults!.rest.skip(1),
    ], mode: ProcessStartMode.inheritStdio);

    return await process.exitCode;
  }
}

class Runner extends CommandRunner<int> {
  late ArgResults _results;

  Runner() : super('pub_command_runner', 'Tests the embeddable pub command.') {
    addCommand(
      pubCommand(isVerbose: () => _results.flag('verbose'))
        ..addSubcommand(ThrowingCommand())
        ..addSubcommand(EnsurePubspecResolvedCommand())
        ..addSubcommand(GetExecutableForCommandCommand()),
    );
    addCommand(RunCommand());
    argParser.addFlag('verbose');
  }

  @override
  Future<int> run(Iterable<String> args) async {
    try {
      _results = super.parse(args);
      if (_results.flag('verbose')) {
        log.verbosity = log.Verbosity.all;
      }
      return await runCommand(_results);
    } on UsageException catch (error) {
      log.exception(error);
      return exit_codes.USAGE;
    }
  }

  @override
  Future<int> runCommand(ArgResults topLevelResults) async {
    return await super.runCommand(topLevelResults) ?? 0;
  }
}

Future<void> main(List<String> arguments) async {
  exitCode = await Runner().run(arguments);
}
