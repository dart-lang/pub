// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../command.dart';
import '../tokens.dart';

/// Handles the `token remove` pub command.
class TokenRemoveCommand extends PubCommand {
  @override
  String get name => 'remove';
  @override
  String get description => 'Removes a token.';
  @override
  String get invocation => 'pub token remove [--server <url>] [--all]';

  TokenRemoveCommand() {
    argParser.addOption('server', abbr: 's', help: 'Url for the server.');
    argParser.addFlag('all',
        abbr: 'a', help: 'Remove all stored tokens.', negatable: false);
  }
  @override
  void run() {
    if (argResults.wasParsed('all')) {
      removeToken(cache, all: true);
    } else {
      String server = argResults['server'];
      if (server == null || server.isEmpty) {
        usageException('Must specify a server.');
      }
      var validationMessage = validateServer(server);
      if (validationMessage != null) {
        usageException(validationMessage);
      }
      removeToken(cache, server: server);
    }
  }
}
