// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: import_of_legacy_library_into_null_safe

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
    // TODO(themisir): The output interface could be improved even more with
    // additional details line, token preview, token kind, and instructions
    // to remove a token.
    log.message('Found ${cache.tokenStore.tokens.length} entries.');
    for (final scheme in cache.tokenStore.tokens) {
      log.message(scheme.url);
    }
  }
}
