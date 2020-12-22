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
import 'command/build.dart';
import 'command/cache.dart';
import 'command/deps.dart';
import 'command/downgrade.dart';
import 'command/get.dart';
import 'command/global.dart';
import 'command/lish.dart';
import 'command/list_package_dirs.dart';
import 'command/login.dart';
import 'command/logout.dart';
import 'command/outdated.dart';
import 'command/remove.dart';
import 'command/run.dart';
import 'command/serve.dart';
import 'command/upgrade.dart';
import 'command/uploader.dart';
import 'command/version.dart';
import 'exit_codes.dart' as exit_codes;
import 'git.dart' as git;
import 'io.dart';
import 'log.dart' as log;
import 'log.dart';
import 'sdk.dart';

class PubCommandRunner extends CommandRunner<int> implements PubTopLevel {
  @override
  bool get captureStackChains {
    return _argResults['trace'] ||
        _argResults['verbose'] ||
        _argResults['verbosity'] == 'all';
  }

  @override
  Verbosity get verbosity {
    switch (_argResults['verbosity']) {
      case 'error':
        return log.Verbosity.ERROR;
      case 'warning':
        return log.Verbosity.WARNING;
      case 'normal':
        return log.Verbosity.NORMAL;
      case 'io':
        return log.Verbosity.IO;
      case 'solver':
        return log.Verbosity.SOLVER;
      case 'all':
        return log.Verbosity.ALL;
      default:
        // No specific verbosity given, so check for the shortcut.
        if (_argResults['verbose']) return log.Verbosity.ALL;
        return log.Verbosity.NORMAL;
    }
  }

  @override
  bool get trace => _argResults['trace'];

  ArgResults _argResults;

  /// The top-level options parsed by the command runner.
  @override
  ArgResults get argResults => _argResults;

  @override
  String get usageFooter =>
      'See https://dart.dev/tools/pub/cmd for detailed documentation.';

  PubCommandRunner()
      : super('pub', 'Pub is a package manager for Dart.',
            usageLineLength: lineLength) {
    argParser.addFlag('version', negatable: false, help: 'Print pub version.');
    argParser.addFlag('trace',
        help: 'Print debugging information when an error occurs.');
    argParser
        .addOption('verbosity', help: 'Control output verbosity.', allowed: [
      'error',
      'warning',
      'normal',
      'io',
      'solver',
      'all'
    ], allowedHelp: {
      'error': 'Show only errors.',
      'warning': 'Show only errors and warnings.',
      'normal': 'Show errors, warnings, and user messages.',
      'io': 'Also show IO operations.',
      'solver': 'Show steps during version resolution.',
      'all': 'Show all output including internal tracing messages.'
    });
    argParser.addFlag('verbose',
        abbr: 'v', negatable: false, help: 'Shortcut for "--verbosity=all".');

    // When adding new commands be sure to also add them to
    // `pub_embeddable_command.dart`.
    addCommand(AddCommand());
    addCommand(BuildCommand());
    addCommand(CacheCommand());
    addCommand(DepsCommand());
    addCommand(DowngradeCommand());
    addCommand(GlobalCommand());
    addCommand(GetCommand());
    addCommand(ListPackageDirsCommand());
    addCommand(LishCommand());
    addCommand(OutdatedCommand());
    addCommand(RemoveCommand());
    addCommand(RunCommand());
    addCommand(ServeCommand());
    addCommand(UpgradeCommand());
    addCommand(UploaderCommand());
    addCommand(LoginCommand());
    addCommand(LogoutCommand());
    addCommand(VersionCommand());
  }

  @override
  Future<int> run(Iterable<String> args) async {
    _argResults = parse(args);
    return await runCommand(_argResults) ?? exit_codes.SUCCESS;
  }

  @override
  Future<int> runCommand(ArgResults topLevelResults) async {
    _checkDepsSynced();

    if (topLevelResults['version']) {
      log.message('Pub ${sdk.version}');
      return 0;
    }
    try {
      return await super.runCommand(topLevelResults);
    } on UsageException catch (error) {
      log.exception(error);
      return exit_codes.USAGE;
    }
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

    var deps = readTextFile(p.join(dartRepoRoot, 'DEPS'));
    var pubRevRegExp = RegExp(r'^ +"pub_rev": +"@([^"]+)"', multiLine: true);
    var match = pubRevRegExp.firstMatch(deps);
    if (match == null) return;
    var depsRev = match[1];

    String actualRev;
    final pubRoot = p.dirname(p.dirname(p.fromUri(Platform.script)));
    try {
      actualRev =
          git.runSync(['rev-parse', 'HEAD'], workingDir: pubRoot).single;
    } on git.GitException catch (_) {
      // When building for Debian, pub isn't checked out via git.
      return;
    }

    if (depsRev == actualRev) return;
    log.warning("${log.yellow('Warning:')} the revision of pub in DEPS is "
        '${log.bold(depsRev)},\n'
        'but ${log.bold(actualRev)} is checked out in '
        '${p.relative(pubRoot)}.\n\n');
  }
}
