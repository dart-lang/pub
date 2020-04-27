// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import 'entrypoint.dart';
import 'global_packages.dart';
import 'log.dart' as log;
import 'system_cache.dart';

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
abstract class PubCommand extends Command {
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

  @override
  void printUsage() {
    log.message(usage);
  }

  /// Parses a user-supplied integer [intString] named [name].
  ///
  /// If the parsing fails, prints a usage message and exits.
  int parseInt(String intString, String name) {
    try {
      return int.parse(intString);
    } on FormatException catch (_) {
      usageException('Could not parse $name "$intString".');
      return null;
    }
  }
}
