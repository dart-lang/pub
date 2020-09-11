// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../command.dart';
import 'token_add.dart';
import 'token_list.dart';

/// Handles the `token` pub command.
class TokenCommand extends PubCommand {
  @override
  String get name => 'token';
  @override
  String get description => 'Manage tokens for hosted packages.';
  @override
  String get invocation => 'pub token <subcommand>';
  @override
  String get docUrl => 'https://dart.dev/tools/pub/cmd/token';

  TokenCommand() {
    addSubcommand(TokenAddCommand());
    addSubcommand(TokenListCommand());
  }
}
