// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import '../command.dart';
import '../log.dart' as log;
import '../solver.dart';

/// Handles the `get` pub command.
class GetCommand extends PubCommand {
  @override
  String get name => 'get';
  @override
  String get description => "Get the current package's dependencies.";
  @override
  String get docUrl => 'https://dart.dev/tools/pub/cmd/pub-get';
  @override
  bool get isOffline => argResults['offline'];

  GetCommand() {
    argParser.addFlag('offline',
        help: 'Use cached packages instead of accessing the network.');

    argParser.addFlag('dry-run',
        abbr: 'n',
        negatable: false,
        help: "Report what dependencies would change but don't change any.");

    argParser.addFlag('precompile',
        help: 'Build executables in immediate dependencies.');

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
    await entrypoint.acquireDependencies(
      SolveType.get,
      dryRun: argResults['dry-run'],
      precompile: argResults['precompile'],
      analytics: analytics,
    );

    var example = entrypoint.example;
    if (argResults['example'] && example != null) {
      await example.acquireDependencies(SolveType.get,
          dryRun: argResults['dry-run'],
          precompile: argResults['precompile'],
          onlyReportSuccessOrFailure: true,
          analytics: analytics);
    }
  }
}
