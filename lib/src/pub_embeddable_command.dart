// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'command.dart';
import 'command.dart' show PubCommand;
import 'command/add.dart';
import 'command/build.dart';
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
import 'command/upgrade.dart';
import 'command/uploader.dart';
import 'log.dart' as log;
import 'log.dart';

/// Exposes the `pub` commands as a command to be embedded in another command
/// runner such as `dart pub`.
class PubEmbeddableCommand extends PubCommand implements PubTopLevel {
  @override
  String get name => 'pub';
  @override
  String get description => 'Work with packages.';
  @override
  String get docUrl => 'https://dart.dev/tools/pub/cmd/pub-global';

  PubEmbeddableCommand() : super() {
    argParser.addFlag('trace',
        help: 'Print debugging information when an error occurs.');
    argParser.addFlag('verbose',
        abbr: 'v', negatable: false, help: 'Shortcut for "--verbosity=all".');
    // This list is intentionally shorter than the one in
    // pub_command_runner.dart.
    //
    // It does not include deprecated commands we do not want to embed into
    // dartdev.
    //
    // New commands should (most likely) be included in both lists.
    addSubcommand(AddCommand());
    addSubcommand(BuildCommand());
    addSubcommand(CacheCommand());
    addSubcommand(DepsCommand());
    addSubcommand(DowngradeCommand());
    addSubcommand(GlobalCommand(alwaysUseSubprocess: true));
    addSubcommand(GetCommand());
    addSubcommand(LishCommand());
    addSubcommand(OutdatedCommand());
    addSubcommand(RemoveCommand());
    addSubcommand(RunCommand(deprecated: true, alwaysUseSubprocess: true));
    addSubcommand(UpgradeCommand());
    addSubcommand(UploaderCommand());
    addSubcommand(LoginCommand());
    addSubcommand(LogoutCommand());
  }

  @override
  void printUsage() {
    log.message(usage);
  }

  @override
  bool get captureStackChains => argResults['verbose'];

  @override
  Verbosity get verbosity =>
      argResults['verbose'] ? Verbosity.ALL : Verbosity.NORMAL;

  @override
  bool get trace => argResults['verbose'];
}
