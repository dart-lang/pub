// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import '../command.dart';
import '../io.dart' as io;

import '../tokens.dart';

/// Handles the `login` pub command.
class LoginCommand extends PubCommand {
  @override
  String get name => 'login';
  @override
  String get description => 'Log in to third-party pub server.';
  @override
  String get invocation => 'pub login <server>';

  @override
  Future run() async {
    if (argResults.rest.isEmpty) {
      usageException('Must specify a server to log in.');
    }
    var server = argResults.rest.first;
    var validationMessage = validateServer(server);
    if (validationMessage != null) {
      usageException(validationMessage);
    }

    if (argResults.rest.length > 1) {
      usageException('No extra arguments are allowed.');
    }

    var token = io.prompt('Enter a token value');

    if (token == null || token.isEmpty) {
      usageException('No token provided.');
    }

    addToken(cache, server, token);
  }
}
