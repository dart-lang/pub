// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import '../command.dart';
import '../log.dart' as log;
import '../solver.dart';

/// Handles the `upgrade` pub command.
class UpgradeCommand extends PubCommand {
  @override
  String get name => 'upgrade';
  @override
  String get description =>
      "Upgrade the current package's dependencies to latest versions.";
  @override
  String get invocation => 'pub upgrade [dependencies...]';
  @override
  String get docUrl => 'https://dart.dev/tools/pub/cmd/pub-upgrade';

  @override
  bool get isOffline => argResults['offline'];

  String get channel => argResults['channel'];

  UpgradeCommand() {
    argParser.addFlag('offline',
        help: 'Use cached packages instead of accessing the network.');

    argParser.addFlag('dry-run',
        abbr: 'n',
        negatable: false,
        help: "Report what dependencies would change but don't change any.");

    argParser.addFlag('precompile',
        help: 'Precompile executables in immediate dependencies.');

    argParser.addOption('channel',
        help: 'Pre-release channel to allow, matches the first component of '
            'pre-release versions');

    argParser.addFlag('packages-dir', hide: true);
  }

  @override
  Future run() async {
    if (argResults.wasParsed('packages-dir')) {
      log.warning(log.yellow(
          'The --packages-dir flag is no longer used and does nothing.'));
    }
    await entrypoint.acquireDependencies(SolveType.UPGRADE,
        useLatest: argResults.rest,
        dryRun: argResults['dry-run'],
        precompile: argResults['precompile'],
        channel: channel);

    if (isOffline) {
      log.warning('Warning: Upgrading when offline may not update you to the '
          'latest versions of your dependencies.');
    }
  }
}
