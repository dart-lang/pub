// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:collection/collection.dart' show IterableExtension;
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import 'authentication/token_store.dart';
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

final lineLength = _lineLength();

int _lineLength() {
  final fromEnv = Platform.environment['_PUB_TEST_TERMINAL_COLUMNS'];
  if (fromEnv != null) {
    final parsed = int.tryParse(fromEnv);
    if (parsed != null && parsed > 0) return parsed;
  }
  if (stdout.hasTerminal) return stdout.terminalColumns;
  return 80;
}

/// The base class for commands for the pub executable.
///
/// A command may either be a "leaf" command or it may be a parent for a set
/// of subcommands. Only leaf commands are ever actually invoked. If a command
/// has subcommands, then one of those must always be chosen.
abstract class PubCommand extends Command<int> {
  @override
  ArgResults get argResults {
    final a = super.argResults;
    if (a == null) {
      throw StateError(
        'argResults cannot be used before Command.run is called.',
      );
    }
    return a;
  }

  String get directory {
    return (argResults.options.contains('directory')
            ? asString(argResults['directory'])
            : null) ??
        _pubTopLevel.directory;
  }

  late final SystemCache cache = SystemCache(isOffline: isOffline);

  GlobalPackages get globals => _globals ??= GlobalPackages(cache);

  GlobalPackages? _globals;

  TokenStore get tokenStore => cache.tokenStore;

  /// Gets the [Entrypoint] package for the current working directory.
  ///
  /// This will load the pubspec and fail with an error if the current directory
  /// is not a package.
  late final Entrypoint entrypoint = Entrypoint(directory, cache);

  /// The URL for web documentation for this command.
  String? get docUrl => null;

  /// Override this and return `false` to disallow trailing options from being
  /// parsed after a non-option argument is parsed.
  bool get allowTrailingOptions => true;

  // Lazily initialize the parser because the superclass constructor requires
  // it but we want to initialize it based on [allowTrailingOptions].
  @override
  late final ArgParser argParser = ArgParser(
    allowTrailingOptions: allowTrailingOptions,
    usageLineLength: lineLength,
  );

  /// Override this to use offline-only sources instead of hitting the network.
  ///
  /// This will only be called before the [SystemCache] is created. After that,
  /// it has no effect. This only needs to be set in leaf commands.
  bool get isOffline => false;

  @override
  String? get usageFooter {
    if (docUrl == null) return null;
    return 'See $docUrl for detailed documentation.';
  }

  @override
  List<String> get aliases => pubCommandAliases[name] ?? const [];

  /// The first command in the command chain.
  Command get _topCommand {
    Command current = this;
    while (true) {
      var parent = current.parent;
      if (parent == null) return current;
      current = parent;
    }
  }

  PubEmbeddableCommand? get _pubEmbeddableCommand {
    Command? command = this;
    while (command is! PubEmbeddableCommand) {
      if (command == null) {
        return null;
      }
      command = command.parent;
    }

    return command;
  }

  PubTopLevel get _pubTopLevel =>
      _pubEmbeddableCommand ?? runner as PubTopLevel;

  PubAnalytics? get analytics => _pubEmbeddableCommand?.analytics;

  @override
  String get invocation {
    PubCommand? command = this;
    var names = [];
    do {
      names.add(command?.name);
      command = command?.parent as PubCommand?;
    } while (command != null);
    return [
      runner!.executableName,
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
  int? _exitCodeOverride;

  /// Override the exit code that would normally be used when exiting
  /// successfully. Intended to be used by subcommands like `run` that wishes
  /// to control the top-level exit code.
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
    _computeCommand(_pubTopLevel.argResults);
    _decideOnColors(_pubTopLevel.argResults);

    log.verbosity = _pubTopLevel.verbosity;
    log.fine('Pub ${sdk.version}');

    var crashed = false;
    try {
      await captureErrors<void>(
        () async => runProtected(),
        captureStackChains: _pubTopLevel.captureStackChains,
      );
      if (_exitCodeOverride != null) {
        return _exitCodeOverride!;
      }
      return exit_codes.SUCCESS;
    } catch (error, chain) {
      log.exception(error, chain);
      if (_pubTopLevel.trace) {
        log.dumpTranscriptToStdErr();
      } else if (!isUserFacingException(error)) {
        log.error('''
This is an unexpected error. The full log and other details are collected in:

    $transcriptPath

Consider creating an issue on https://github.com/dart-lang/pub/issues/new
and attaching the relevant parts of that log file.
''');
        crashed = true;
      }
      return _chooseExitCode(error);
    } finally {
      final verbose = _pubTopLevel.verbosity == log.Verbosity.all;

      // Write the whole log transcript to file.
      if (verbose || crashed) {
        // Escape the argument for users to copy-paste in bash.
        // Wrap with single quotation, and use '\'' to insert single quote, as
        // long as we have no spaces this doesn't create a new argument.
        String protectArgument(String x) =>
            RegExp(r'^[a-zA-Z0-9-_]+$').stringMatch(x) == null
                ? "'${x.replaceAll("'", r"'\''")}'"
                : x;

        late final Entrypoint? e;
        try {
          e = entrypoint;
        } on ApplicationException {
          e = null;
        }
        log.dumpTranscriptToFile(
          transcriptPath,
          'dart pub ${_topCommand.argResults!.arguments.map(protectArgument).join(' ')}',
          e,
        );

        if (!crashed) {
          log.message('Logs written to $transcriptPath.');
        }
      }
      globalHttpClient.close();
    }
  }

  /// Returns the appropriate exit code for [exception], falling back on 1 if no
  /// appropriate exit code could be found.
  int _chooseExitCode(Object exception) {
    if (exception is SolveFailure) {
      var packageNotFound = exception.packageNotFound;
      if (packageNotFound != null) exception = packageNotFound;
    }
    while (exception is WrappedException && exception.innerError is Exception) {
      exception = exception.innerError!;
    }

    if (exception is PackageIntegrityException) {
      return exit_codes.TEMP_FAIL;
    } else if (exception is HttpException ||
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

  static String? _command;

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
  static final String command = _command ?? '';

  static void _decideOnColors(ArgResults argResults) {
    if (!argResults.wasParsed('color')) {
      forceColors = ForceColorOption.auto;
    } else {
      forceColors = argResults['color'] as bool
          ? ForceColorOption.always
          : ForceColorOption.never;
    }
  }

  static void _computeCommand(ArgResults argResults) {
    var list = <String?>[];
    for (var command = argResults.command;
        command != null;
        command = command.command) {
      var commandName = command.name;

      if (list.isEmpty) {
        // this is a top-level command
        final rootCommand = pubCommandAliases.entries.singleWhereOrNull(
          (element) => element.value.contains(command!.name),
        );
        if (rootCommand != null) {
          commandName = rootCommand.key;
        }
      }
      list.add(commandName);
    }
    _command = list.join(' ');
  }

  String get transcriptPath {
    return p.join(cache.rootDir, 'log', 'pub_log.txt');
  }
}

abstract class PubTopLevel {
  bool get captureStackChains;
  log.Verbosity get verbosity;
  bool get trace;

  static addColorFlag(ArgParser argParser) {
    argParser.addFlag(
      'color',
      help: 'Use colors in terminal output.\n'
          'Defaults to color when connected to a '
          'terminal, and no-color otherwise.',
    );
  }

  /// The directory containing the pubspec.yaml of the project to work on.
  String get directory;

  /// The argResults from the level of parsing of the 'pub' command.
  ArgResults get argResults;
}
