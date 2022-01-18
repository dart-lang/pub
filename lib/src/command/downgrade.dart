// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import '../command.dart';
import '../log.dart' as log;
import '../solver.dart';

/// Handles the `downgrade` pub command.
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
  bool get isOffline => argResults['offline'];

  DowngradeCommand() {
    argParser.addFlag('offline',
        help: 'Use cached packages instead of accessing the network.');

    argParser.addFlag('dry-run',
        abbr: 'n',
        negatable: false,
        help: "Report what dependencies would change but don't change any.");

    argParser.addFlag('packages-dir', hide: true);

    argParser.addFlag(
      'example',
      help: 'Also run in `example/` (if it exists).',
      hide: true,
    );

    argParser.addOption('directory',
        abbr: 'C', help: 'Run this in the directory<dir>.', valueHelp: 'dir');
  }

  @override
  Future<void> runProtected() async {
    if (argResults.wasParsed('packages-dir')) {
      log.warning(log.yellow(
          'The --packages-dir flag is no longer used and does nothing.'));
    }
    var dryRun = argResults['dry-run'];

    await entrypoint.acquireDependencies(
      SolveType.downgrade,
      unlock: argResults.rest,
      dryRun: dryRun,
      analytics: analytics,
    );
    var example = entrypoint.example;
    if (argResults['example'] && example != null) {
      await example.acquireDependencies(
        SolveType.get,
        unlock: argResults.rest,
        dryRun: dryRun,
        onlyReportSuccessOrFailure: true,
        analytics: analytics,
      );
    }

    if (isOffline) {
      log.warning('Warning: Downgrading when offline may not update you to '
          'the oldest versions of your dependencies.');
    }
  }
}
