// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: import_of_legacy_library_into_null_safe

import '../command.dart';
import '../log.dart' as log;

/// Handles the `token remove` pub command.
class TokenRemoveCommand extends PubCommand {
  @override
  String get name => 'remove';
  @override
  String get description => 'Remove token for server.';
  @override
  String get invocation => 'pub token remove';

  bool get isAll => argResults['all'];

  TokenRemoveCommand() {
    argParser.addFlag('all',
        help: 'Removes all saved tokens from token store.');
  }

  @override
  Future<void> runProtected() async {
    if (isAll) {
      return tokenStore.deleteTokensFile();
    }

    if (argResults.rest.isEmpty) {
      usageException('Must specify a package to be added.');
    } else if (argResults.rest.length > 1) {
      usageException('Takes only a single argument.');
    }

    final hostedUrl = argResults.rest.first;
    final found = tokenStore.removeMatchingTokens(hostedUrl);

    if (found) {
      log.message('Token removed for server $hostedUrl.');
    } else {
      log.message('No saved token found for $hostedUrl.');
    }
  }
}
