// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart=2.10

import 'dart:async';

import '../command.dart';
import '../oauth2.dart' as oauth2;

/// Handles the `logout` pub command.
class LogoutCommand extends PubCommand {
  @override
  String get name => 'logout';
  @override
  String get description => 'Log out of pub.dev.';
  @override
  bool get takesArguments => true;

  LogoutCommand();

  @override
  Future<void> runProtected() async {
    if (argResults.rest.isEmpty) {
      oauth2.logout(cache);
    } else {
      credentialStore.removeServer(argResults.rest.first);
    }
  }
}
