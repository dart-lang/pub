// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'command.dart' show pubCommandAliases, lineLength;
import 'command/build.dart';
import 'command/cache.dart';
import 'command/deps.dart';
import 'command/downgrade.dart';
import 'command/get.dart';
import 'command/global.dart';
import 'command/lish.dart';
import 'command/list_package_dirs.dart';
import 'command/logout.dart';
import 'command/outdated.dart';
import 'command/run.dart';
import 'command/serve.dart';
import 'command/upgrade.dart';
import 'command/uploader.dart';
import 'command/version.dart';
import 'exceptions.dart';
import 'exit_codes.dart' as exit_codes;
import 'git.dart' as git;
import 'http.dart';
import 'io.dart';
import 'log.dart' as log;
import 'sdk.dart';
import 'solver.dart';
import 'utils.dart';

class PubCommandRunner extends CommandRunner {
  /// Returns the nested name of the command that's currently being run.
  /// Examples:
  ///
  ///     get
  ///     cache repair
  ///
  /// Returns an empty string if no command is being run. (This is only
  /// expected to happen when unit tests invoke code inside pub without going
  /// through a command.)
  ///
  /// For top-level commands, if an alias is used, the primary command name is
  /// returned. For instance `install` becomes `get`.
  static String get command {
    if (_options == null) return '';

    var list = <String>[];
    for (var command = _options.command;
        command != null;
        command = command.command) {
      var commandName = command.name;

      if (list.isEmpty) {
        // this is a top-level command
        final rootCommand = pubCommandAliases.entries.singleWhere(
            (element) => element.value.contains(command.name),
            orElse: () => null);
        if (rootCommand != null) {
          commandName = rootCommand.key;
        }
      }
      list.add(commandName);
    }
    return list.join(' ');
  }

  /// The top-level options parsed by the command runner.
  static ArgResults _options;

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
    argParser.addFlag('with-prejudice',
        hide: !isAprilFools,
        negatable: false,
        help: 'Execute commands with prejudice.');
    argParser.addFlag('sparkle',
        hide: !isAprilFools,
        negatable: false,
        help: 'A more sparkly experience.');

    addCommand(BuildCommand());
    addCommand(CacheCommand());
    addCommand(DepsCommand());
    addCommand(DowngradeCommand());
    addCommand(GlobalCommand());
    addCommand(GetCommand());
    addCommand(ListPackageDirsCommand());
    addCommand(LishCommand());
    addCommand(OutdatedCommand());
    addCommand(RunCommand());
    addCommand(ServeCommand());
    addCommand(UpgradeCommand());
    addCommand(UploaderCommand());
    addCommand(LogoutCommand());
    addCommand(VersionCommand());
  }

  @override
  Future run(Iterable<String> args) async {
    try {
      _options = super.parse(args);
    } on UsageException catch (error) {
      log.exception(error);
      await flushThenExit(exit_codes.USAGE);
    }
    await runCommand(_options);
  }

  @override
  Future runCommand(ArgResults topLevelResults) async {
    log.withPrejudice = topLevelResults['with-prejudice'];
    log.sparkle = topLevelResults['sparkle'];

    _checkDepsSynced();

    if (topLevelResults['version']) {
      log.message('Pub ${sdk.version}');
      return;
    }

    if (topLevelResults['trace']) {
      log.recordTranscript();
    }

    switch (topLevelResults['verbosity']) {
      case 'error':
        log.verbosity = log.Verbosity.ERROR;
        break;
      case 'warning':
        log.verbosity = log.Verbosity.WARNING;
        break;
      case 'normal':
        log.verbosity = log.Verbosity.NORMAL;
        break;
      case 'io':
        log.verbosity = log.Verbosity.IO;
        break;
      case 'solver':
        log.verbosity = log.Verbosity.SOLVER;
        break;
      case 'all':
        log.verbosity = log.Verbosity.ALL;
        break;
      default:
        // No specific verbosity given, so check for the shortcut.
        if (topLevelResults['verbose']) log.verbosity = log.Verbosity.ALL;
        break;
    }

    log.fine('Pub ${sdk.version}');

    await _validatePlatform();

    var captureStackChains = topLevelResults['trace'] ||
        topLevelResults['verbose'] ||
        topLevelResults['verbosity'] == 'all';

    try {
      await captureErrors(() => super.runCommand(topLevelResults),
          captureStackChains: captureStackChains);

      // Explicitly exit on success to ensure that any dangling dart:io handles
      // don't cause the process to never terminate.
      await flushThenExit(exit_codes.SUCCESS);
    } catch (error, chain) {
      log.exception(error, chain);

      if (topLevelResults['trace']) {
        log.dumpTranscript();
      } else if (!isUserFacingException(error)) {
        // Escape the argument for users to copy-paste in bash.
        // Wrap with single quotation, and use '\'' to insert single quote, as
        // long as we have no spaces this doesn't create a new argument.
        String protectArgument(String x) =>
            RegExp(r'^[a-zA-Z0-9-_]+$').stringMatch(x) == null
                ? "'${x.replaceAll("'", r"'\''")}'"
                : x;
        log.error("""
This is an unexpected error. Please run

    pub --trace ${topLevelResults.arguments.map(protectArgument).join(' ')}

and include the logs in an issue on https://github.com/dart-lang/pub/issues/new
""");
      }

      await flushThenExit(_chooseExitCode(error));
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

  /// Returns the appropriate exit code for [exception], falling back on 1 if no
  /// appropriate exit code could be found.
  int _chooseExitCode(exception) {
    if (exception is SolveFailure) {
      var packageNotFound = exception.packageNotFound;
      if (packageNotFound != null) exception = packageNotFound;
    }
    while (exception is WrappedException && exception.innerError is Exception) {
      exception = exception.innerError;
    }

    if (exception is HttpException ||
        exception is http.ClientException ||
        exception is SocketException ||
        exception is TlsException ||
        exception is PubHttpException ||
        exception is git.GitException ||
        exception is PackageNotFoundException) {
      return exit_codes.UNAVAILABLE;
    } else if (exception is FileSystemException || exception is FileException) {
      return exit_codes.NO_INPUT;
    } else if (exception is FormatException || exception is DataException) {
      return exit_codes.DATA;
    } else if (exception is ConfigException) {
      return exit_codes.CONFIG;
    } else if (exception is UsageException) {
      return exit_codes.USAGE;
    } else {
      return 1;
    }
  }

  /// Checks that pub is running on a supported platform.
  ///
  /// If it isn't, it prints an error message and exits. Completes when the
  /// validation is done.
  Future _validatePlatform() async {
    if (!Platform.isWindows) return;

    var result = await runProcess('ver', []);
    if (result.stdout.join('\n').contains('XP')) {
      log.error('Sorry, but pub is not supported on Windows XP.');
      await flushThenExit(exit_codes.USAGE);
    }
  }
}
