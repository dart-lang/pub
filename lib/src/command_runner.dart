// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import 'command.dart' show PubTopLevel, lineLength;
import 'command/add.dart';
import 'command/bump.dart';
import 'command/cache.dart';
import 'command/deps.dart';
import 'command/downgrade.dart';
import 'command/get.dart';
import 'command/global.dart';
import 'command/lish.dart';
import 'command/login.dart';
import 'command/logout.dart';
import 'command/outdated.dart';
import 'command/remove.dart';
import 'command/run.dart';
import 'command/token.dart';
import 'command/unpack.dart';
import 'command/upgrade.dart';
import 'command/uploader.dart';
import 'command/version.dart';
import 'command/workspace.dart';
import 'exit_codes.dart' as exit_codes;
import 'git.dart' as git;
import 'io.dart';
import 'log.dart' as log;
import 'log.dart';
import 'sdk.dart';
import 'utils.dart';

/// The name of the program that is invoking pub
/// 'flutter' if we are running inside `flutter pub` 'dart' otherwise.
String topLevelProgram = _isRunningInsideFlutter ? 'flutter' : 'dart';

bool _isRunningInsideFlutter = (Platform.environment['PUB_ENVIRONMENT'] ?? '')
    .contains('flutter_cli');

class PubCommandRunner extends CommandRunner<int> implements PubTopLevel {
  @override
  String get directory => argResults.optionWithDefault('directory');

  @override
  bool get captureStackChains {
    return argResults.flag('trace') ||
        argResults.flag('verbose') ||
        argResults.option('verbosity') == 'all';
  }

  @override
  Verbosity get verbosity {
    switch (argResults['verbosity']) {
      case 'error':
        return log.Verbosity.error;
      case 'warning':
        return log.Verbosity.warning;
      case 'normal':
        return log.Verbosity.normal;
      case 'io':
        return log.Verbosity.io;
      case 'solver':
        return log.Verbosity.solver;
      case 'all':
        return log.Verbosity.all;
      default:
        // No specific verbosity given, so check for the shortcut.
        if (argResults.flag('verbose')) return log.Verbosity.all;
        if (runningFromTest) return log.Verbosity.testing;
        return log.Verbosity.normal;
    }
  }

  @override
  bool get trace => argResults.flag('trace');

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

  @override
  String get usageFooter =>
      'See https://dart.dev/tools/pub/cmd for detailed documentation.';

  PubCommandRunner()
    : super(
        'pub',
        'Pub is a package manager for Dart.',
        usageLineLength: lineLength,
      ) {
    argParser.addFlag('version', negatable: false, help: 'Print pub version.');
    argParser.addFlag(
      'trace',
      help: 'Print debugging information when an error occurs.',
    );
    argParser.addOption(
      'verbosity',
      help: 'Control output verbosity.',
      allowed: ['error', 'warning', 'normal', 'io', 'solver', 'all'],
      allowedHelp: {
        'error': 'Show only errors.',
        'warning': 'Show only errors and warnings.',
        'normal': 'Show errors, warnings, and user messages.',
        'io': 'Also show IO operations.',
        'solver': 'Show steps during version resolution.',
        'all': 'Show all output including internal tracing messages.',
      },
    );
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

    // When adding new commands be sure to also add them to
    // `pub_embeddable_command.dart`.
    addCommand(AddCommand());
    addCommand(BumpCommand());
    addCommand(CacheCommand());
    addCommand(DepsCommand());
    addCommand(DowngradeCommand());
    addCommand(GlobalCommand());
    addCommand(GetCommand());
    addCommand(LishCommand());
    addCommand(OutdatedCommand());
    addCommand(RemoveCommand());
    addCommand(RunCommand());
    addCommand(UpgradeCommand());
    addCommand(UnpackCommand());
    addCommand(UploaderCommand());
    addCommand(LoginCommand());
    addCommand(LogoutCommand());
    addCommand(VersionCommand());
    addCommand(WorkspaceCommand());
    addCommand(TokenCommand());
  }

  @override
  Future<int> run(Iterable<String> args) async {
    try {
      final argResults = parse(args);
      _argResults = argResults;
      return await runCommand(argResults) ?? exit_codes.SUCCESS;
    } on UsageException catch (error) {
      log.exception(error);
      return exit_codes.USAGE;
    }
  }

  @override
  Future<int?> runCommand(ArgResults topLevelResults) async {
    _checkDepsSynced();

    if (topLevelResults.flag('version')) {
      log.message('Pub ${sdk.version}');
      return 0;
    }
    return await super.runCommand(topLevelResults);
  }

  @override
  void printUsage() {
    log.message(usage);
  }

  /// Print a warning if we're running from the Dart SDK repo and pub isn't
  /// up-to-date.
  ///
  /// This is otherwise hard to tell, and can produce confusing behavior issues.
  void _checkDepsSynced() {
    if (!runningFromDartRepo) return;
    if (!git.isInstalled) return;

    final deps = readTextFile(p.join(dartRepoRoot, 'DEPS'));
    final pubRevRegExp = RegExp(r'^ +"pub_rev": +"@([^"]+)"', multiLine: true);
    final match = pubRevRegExp.firstMatch(deps);
    if (match == null) return;
    final depsRev = match[1];

    String actualRev;
    final pubRoot = p.dirname(p.dirname(p.fromUri(Platform.script)));
    try {
      actualRev =
          git.runSync(['rev-parse', 'HEAD'], workingDir: pubRoot).trim();
    } on git.GitException catch (_) {
      // When building for Debian, pub isn't checked out via git.
      return;
    }

    if (depsRev == actualRev) return;
    log.warning(
      "${log.yellow('Warning:')} the revision of pub in DEPS is "
      '${log.bold(depsRev.toString())},\n'
      'but ${log.bold(actualRev)} is checked out in '
      '${p.relative(pubRoot)}.\n\n',
    );
  }
}
