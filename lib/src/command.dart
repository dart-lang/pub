// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import 'command_runner.dart';
import 'entrypoint.dart';
import 'exceptions.dart';
import 'exit_codes.dart' as exit_codes;
import 'git.dart' as git;
import 'global_packages.dart';
import 'http.dart';
import 'log.dart' as log;
import 'pub_embeddable_command.dart';
import 'sdk.dart';
import 'solver.dart';
import 'system_cache.dart';
import 'utils.dart';

/// All of the aliases used for [PubCommand] subclasses.
///
/// Centralized so invocations with aliases can be normalized to the primary
/// command name when sending telemetry.
const pubCommandAliases = {
  'deps': ['dependencies', 'tab'],
  'get': ['install'],
  'publish': ['lish', 'lush'],
  'upgrade': ['update'],
};

final lineLength = stdout.hasTerminal ? stdout.terminalColumns : 80;

/// The base class for commands for the pub executable.
///
/// A command may either be a "leaf" command or it may be a parent for a set
/// of subcommands. Only leaf commands are ever actually invoked. If a command
/// has subcommands, then one of those must always be chosen.
abstract class PubCommand extends Command<int> {
  SystemCache get cache => _cache ??= SystemCache(isOffline: isOffline);

  SystemCache _cache;

  GlobalPackages get globals => _globals ??= GlobalPackages(cache);

  GlobalPackages _globals;

  /// Gets the [Entrypoint] package for the current working directory.
  ///
  /// This will load the pubspec and fail with an error if the current directory
  /// is not a package.
  Entrypoint get entrypoint => _entrypoint ??= Entrypoint.current(cache);

  Entrypoint _entrypoint;

  /// The URL for web documentation for this command.
  String get docUrl => null;

  /// Override this and return `false` to disallow trailing options from being
  /// parsed after a non-option argument is parsed.
  bool get allowTrailingOptions => true;

  // Lazily initialize the parser because the superclass constructor requires
  // it but we want to initialize it based on [allowTrailingOptions].
  @override
  ArgParser get argParser => _argParser ??= ArgParser(
      allowTrailingOptions: allowTrailingOptions, usageLineLength: lineLength);

  ArgParser _argParser;

  /// Override this to use offline-only sources instead of hitting the network.
  ///
  /// This will only be called before the [SystemCache] is created. After that,
  /// it has no effect. This only needs to be set in leaf commands.
  bool get isOffline => false;

  @override
  String get usageFooter {
    if (docUrl == null) return null;
    return 'See $docUrl for detailed documentation.';
  }

  @override
  List<String> get aliases => pubCommandAliases[name] ?? const [];

  /// The first command in the command chain.
  Command get _topCommand {
    var command = this;
    while (command.parent != null) {
      command = command.parent;
    }
    return command;
  }

  PubEmbeddableCommand get _pubEmbeddableCommand {
    var command = this;
    while (command != null && command is! PubEmbeddableCommand) {
      command = command.parent;
    }
    return command;
  }

  PubTopLevel get _pubTopLevel {
    return _pubEmbeddableCommand ?? (runner as PubCommandRunner);
  }

  @override
  String get invocation {
    var command = this;
    var names = [];
    do {
      names.add(command.name);
      command = command.parent;
    } while (command != null);
    return [
      runner.executableName,
      ...names.reversed,
      argumentsDescription,
    ].join(' ');
  }

  /// Short description of how the arguments should be provided in `invocation`.
  ///
  /// Override for giving a more detailed description.
  String get argumentsDescription => subcommands.isEmpty
      ? '<subcommand> [arguments...]'
      : (takesArguments ? '[arguments...]' : '');

  /// If not `null` this overrides the default exit-code [exit_codes.SUCCESS]
  /// when exiting successfully.
  ///
  /// This should only be modified by [overrideExitCode].
  int _exitCodeOverride;

  /// Override the exit code that would normally be used when exiting
  /// successfully. Intended to be used by subcommands like `run` that wishes
  /// to control the top-level exitcode.
  ///
  /// This may only be called once.
  @nonVirtual
  @protected
  void overrideExitCode(int exitCode) {
    assert(_exitCodeOverride == null, 'overrideExitCode was called twice!');
    _exitCodeOverride = exitCode;
  }

  @override
  @nonVirtual
  FutureOr<int> run() async {
    computeCommand(_pubTopLevel.argResults);
    if (_pubTopLevel.trace) {
      log.recordTranscript();
    }
    log.verbosity = _pubTopLevel.verbosity;
    log.fine('Pub ${sdk.version}');

    try {
      await captureErrors(runProtected,
          captureStackChains: _pubTopLevel.captureStackChains);
      if (_exitCodeOverride != null) {
        return _exitCodeOverride;
      }
      return exit_codes.SUCCESS;
    } catch (error, chain) {
      log.exception(error, chain);

      if (_pubTopLevel.trace) {
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

    pub --trace ${runner.executableName} ${_topCommand.name} ${_topCommand.argResults.arguments.map(protectArgument).join(' ')}

and include the logs in an issue on https://github.com/dart-lang/pub/issues/new
""");
      }
      return _chooseExitCode(error);
    } finally {
      httpClient.close();
    }
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

  /// Override this in leaf commands to run a pub command with pub error
  /// handling.
  FutureOr<void> runProtected() {
    throw UnimplementedError('All leaf commands should override this');
  }

  @override
  void printUsage() {
    log.message(usage);
  }

  static String _command;

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
  static String get command => _command;

  static void computeCommand(ArgResults argResults) {
    var list = <String>[];
    for (var command = argResults.command;
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
    _command = list.join(' ');
  }
}

abstract class PubTopLevel {
  bool get captureStackChains;
  log.Verbosity get verbosity;
  bool get trace;

  /// The argResults from the level of parsing of the 'pub' command.
  ArgResults get argResults;
}
