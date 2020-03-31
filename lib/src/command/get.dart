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
  String get invocation => 'pub get';
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
        defaultsTo: false,
        help: 'Precompile executables in immediate dependencies.');

    argParser.addFlag('packages-dir', negatable: true, hide: true);
  }

  @override
  Future run() {
    if (argResults.wasParsed('packages-dir')) {
      log.warning(log.yellow(
          'The --packages-dir flag is no longer used and does nothing.'));
    }
    return entrypoint.acquireDependencies(SolveType.GET,
        dryRun: argResults['dry-run'], precompile: argResults['precompile']);
  }
}
