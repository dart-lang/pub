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
  String get description => 'Log in to hosted server.';
  @override
  String get invocation => 'pub login <server> [--token <secret>]';

  LoginCommand() {
    argParser.addOption('token',
        abbr: 't',
        help: 'Token. Environment variable can be used with \'\$YOUR_VAR\'.');
  }

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

    String token = argResults['token'];
    if (token == null || token.isEmpty) {
      token = await io.prompt(
          'Enter a token value (prefix with \$ for environment variable)');
      if (token == null || token.isEmpty) return;
    }

    addToken(cache, server, token);
  }
}
