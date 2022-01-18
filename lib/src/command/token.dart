// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../command.dart';
import 'token_add.dart';
import 'token_list.dart';
import 'token_remove.dart';

/// Handles the `token` command.
class TokenCommand extends PubCommand {
  @override
  String get name => 'token';
  @override
  String get description =>
      'Manage authentication tokens for hosted pub repositories.';

  TokenCommand() {
    addSubcommand(TokenListCommand());
    addSubcommand(TokenAddCommand());
    addSubcommand(TokenRemoveCommand());
  }
}
