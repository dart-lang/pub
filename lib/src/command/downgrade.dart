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
      "Downgrade the current package's dependencies to oldest versions.\n\n"
      "This doesn't modify the lockfile, so it can be reset with \"pub get\".";
  @override
  String get invocation => 'pub downgrade [dependencies...]';
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

    argParser.addFlag('packages-dir', negatable: true, hide: true);
  }

  @override
  Future run() async {
    if (argResults.wasParsed('packages-dir')) {
      log.warning(log.yellow(
          'The --packages-dir flag is no longer used and does nothing.'));
    }
    var dryRun = argResults['dry-run'];
    await entrypoint.acquireDependencies(SolveType.DOWNGRADE,
        useLatest: argResults.rest, dryRun: dryRun);

    if (isOffline) {
      log.warning('Warning: Downgrading when offline may not update you to '
          'the oldest versions of your dependencies.');
    }
  }
}
