// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart=2.10

import 'dart:async';

import '../command.dart';
import '../io.dart';
import '../oauth2.dart' as oauth2;

/// Handles the `logout` pub command.
class LogoutCommand extends PubCommand {
  @override
  String get name => 'logout';
  @override
  String get description => 'Log out of pub.dev.';
  @override
  bool get takesArguments => true;

  String get server => argResults['server'];
  bool get clear => argResults['clear'];

  LogoutCommand() {
    argParser.addOption('server',
        help: 'The package server to which needs to be authenticated.');

    argParser.addFlag('clear',
        help: 'Removes all of previously saved credentials for hosted pub '
            'servers',
        defaultsTo: false);
  }

  @override
  Future<void> runProtected() async {
    if (clear) {
      if (await confirm('Are you sure you want to remove all credentials')) {
        tokenStore.deleteTokensFile();
      }
    } else if (server == null) {
      oauth2.logout(cache);
    } else {
      tokenStore.removeMatchingTokens(server);
    }
  }
}
