// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'command.dart' show PubCommand, PubTopLevel;
import 'command.dart';
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
import 'command/workspace.dart';
import 'log.dart' as log;
import 'log.dart';
import 'utils.dart';

/// Exposes the `pub` commands as a command to be embedded in another command
/// runner such as `dart pub`.
class PubEmbeddableCommand extends PubCommand implements PubTopLevel {
  @override
  String get name => 'pub';

  @override
  List<String> get suggestionAliases => const ['packages', 'pkg'];

  @override
  String get description => 'Work with packages.';
  @override
  String get docUrl => 'https://dart.dev/tools/pub/cmd/pub-global';

  @override
  String get directory => argResults.optionWithDefault('directory');

  final bool Function() isVerbose;

  @override
  final String category;

  PubEmbeddableCommand(this.isVerbose, this.category) : super() {
    // This flag was never honored in the embedding but since it was accepted we
    // leave it as a hidden flag to avoid breaking clients that pass it.
    argParser.addFlag('trace', hide: true);
    argParser.addFlag(
      'verbose',
      abbr: 'v',
      negatable: false,
      help: 'Print detailed logging.',
    );
    PubTopLevel.addColorFlag(argParser);
    argParser.addOption(
      'directory',
      abbr: 'C',
      help: 'Run the subcommand in the directory<dir>.',
      defaultsTo: '.',
      valueHelp: 'dir',
    );
    // This list is intentionally shorter than the one in
    // pub_command_runner.dart.
    //
    // It does not include deprecated commands we do not want to embed into
    // dartdev.
    //
    // New commands should (most likely) be included in both lists.
    addSubcommand(AddCommand());
    addSubcommand(BumpCommand());
    addSubcommand(CacheCommand());
    addSubcommand(DepsCommand());
    addSubcommand(DowngradeCommand());
    addSubcommand(GlobalCommand(alwaysUseSubprocess: true));
    addSubcommand(GetCommand());
    addSubcommand(LishCommand());
    addSubcommand(OutdatedCommand());
    addSubcommand(RemoveCommand());
    addSubcommand(RunCommand(deprecated: true, alwaysUseSubprocess: true));
    addSubcommand(UnpackCommand());
    addSubcommand(UpgradeCommand());
    addSubcommand(UploaderCommand());
    addSubcommand(LoginCommand());
    addSubcommand(LogoutCommand());
    addSubcommand(TokenCommand());
    addSubcommand(WorkspaceCommand());
  }

  @override
  void printUsage() {
    log.message(usage);
  }

  @override
  bool get captureStackChains => _isVerbose;

  @override
  Verbosity get verbosity => _isVerbose ? Verbosity.all : Verbosity.normal;

  @override
  bool get trace => _isVerbose;

  bool get _isVerbose {
    return argResults.flag('verbose') || isVerbose();
  }
}
