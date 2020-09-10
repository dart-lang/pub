// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../command.dart';
import '../tokens.dart';

/// Handles the `token add` pub command.
class TokenAddCommand extends PubCommand {
  @override
  String get name => 'add';
  @override
  String get description => 'Add a token.';
  @override
  String get invocation => 'pub token add --server <url> --token <value>';

  TokenAddCommand() {
    argParser.addOption('server', abbr: 's', help: 'Url for the server.');
    argParser.addOption('token',
        abbr: 't',
        help: 'Token. Environment variable can be used with \'\$YOUR_VAR\'.');
  }

  @override
  void run() {
    String server = argResults['server'];
    String token = argResults['token'];

    if (server == null || server.isEmpty || token == null || token.isEmpty) {
      usageException('Must specify both server and token.');
    }

    var validationMessage = validateServer(server);
    if (validationMessage != null) {
      usageException(validationMessage);
    }

    addToken(cache, server, token);
  }
}
