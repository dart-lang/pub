// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import '../command.dart';
import '../command_runner.dart';
import '../log.dart' as log;
import '../solver.dart';

class DowngradeCommand extends PubCommand {
  @override
  String get name => 'downgrade';
  @override
  String get description =>
      "Downgrade the current package's dependencies to oldest versions.\n\n";
  @override
  String get argumentsDescription => '[dependencies...]';
  @override
  String get docUrl => 'https://dart.dev/tools/pub/cmd/pub-downgrade';

  @override
  bool get isOffline => argResults.flag('offline');

  bool get _dryRun => argResults.flag('dry-run');

  bool get _tighten => argResults.flag('tighten');

  bool get _example => argResults.flag('example');

  DowngradeCommand() {
    argParser.addFlag(
      'offline',
      help: 'Use cached packages instead of accessing the network.',
    );

    argParser.addFlag(
      'dry-run',
      abbr: 'n',
      negatable: false,
      help: "Report what dependencies would change but don't change any.",
    );

    argParser.addFlag('packages-dir', hide: true);

    argParser.addFlag(
      'example',
      defaultsTo: true,
      help: 'Also run in `example/` (if it exists).',
      hide: true,
    );

    argParser.addOption(
      'directory',
      abbr: 'C',
      help: 'Run this in the directory <dir>.',
      valueHelp: 'dir',
    );

    argParser.addFlag(
      'tighten',
      help:
          'Updates lower bounds in pubspec.yaml to match the resolved version.',
      negatable: false,
    );
  }

  @override
  Future<void> runProtected() async {
    if (argResults.wasParsed('packages-dir')) {
      log.warning(
        log.yellow(
          'The --packages-dir flag is no longer used and does nothing.',
        ),
      );
    }

    await entrypoint.acquireDependencies(
      SolveType.downgrade,
      unlock: argResults.rest,
      dryRun: _dryRun,
    );
    final example = entrypoint.example;
    if (argResults.flag('example') && example != null) {
      await example.acquireDependencies(
        SolveType.get,
        unlock: argResults.rest,
        dryRun: _dryRun,
        summaryOnly: true,
      );
    }

    if (_tighten) {
      if (_example && entrypoint.example != null) {
        log.warning(
          'Running `downgrade --tighten` only in `${entrypoint.workspaceRoot.dir}`. Run `$topLevelProgram pub upgrade --tighten --directory example/` separately.',
        );
      }
      final changes = entrypoint.tighten();
      entrypoint.applyChanges(changes, _dryRun);
    }

    if (isOffline) {
      log.warning('Warning: Downgrading when offline may not update you to '
          'the oldest versions of your dependencies.');
    }
  }
}
