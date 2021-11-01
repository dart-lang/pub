// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../command.dart';
import '../log.dart' as log;

/// Handles the `token list` pub command.
class TokenListCommand extends PubCommand {
  @override
  String get name => 'list';
  @override
  String get description => 'List servers for which a token exists.';
  @override
  String get invocation => 'pub token list';

  @override
  Future<void> runProtected() async {
    if (cache.tokenStore.credentials.isNotEmpty) {
      log.message(
        'You have secret tokens for ${cache.tokenStore.credentials.length} package '
        'repositories:',
      );
      for (final token in cache.tokenStore.credentials) {
        log.message(token.url);
      }
    } else {
      log.message(
        'You do not have any secret tokens for package repositories.\n'
        'However you can add new tokens using the command below:\n'
        '\n    pub token add [hosted-url]',
      );
    }
  }
}
