// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import '../command.dart';
import '../oauth2.dart' as oauth2;
import '../tokens.dart';

/// Handles the `logout` pub command.
class LogoutCommand extends PubCommand {
  @override
  String get name => 'logout';
  @override
  String get description => 'Log out of pub.dev or any third-party pub server.';
  @override
  bool get takesArguments => false;

  /// Whether to log out of all servers, including third-party pub servers.
  bool get _all => argResults['all'];

  LogoutCommand() {
    argParser.addFlag('all',
        abbr: 'a',
        negatable: false,
        help: 'Log out of all servers (pub.dev and third-party pub serves).');
  }

  @override
  Future<void> runProtected() async {
    oauth2.logout(cache);
  }
}
