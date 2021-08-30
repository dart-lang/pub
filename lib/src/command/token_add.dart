// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: import_of_legacy_library_into_null_safe

import 'dart:async';

import '../authentication/token.dart';
import '../command.dart';
import '../io.dart';
import '../log.dart' as log;
import '../source/hosted.dart';

/// Handles the `token add` pub command.
class TokenAddCommand extends PubCommand {
  @override
  String get name => 'add';
  @override
  String get description => 'Add token for a server.';
  @override
  String get invocation => 'pub token add';

  @override
  Future<void> runProtected() async {
    if (argResults.rest.isEmpty) {
      usageException('Must specify a hosted server URL to be added.');
    } else if (argResults.rest.length > 1) {
      usageException('Takes only a single argument.');
    }

    try {
      var hostedUrl = validateAndNormalizeHostedUrl(argResults.rest.first);

      if (hostedUrl.isScheme('HTTP')) {
        // TODO(themisir): Improve the following message.
        usageException('Unsecure pub server could not be added.');
      }

      final token = await readLine('Please enter bearer token')
          .timeout(const Duration(minutes: 5));

      if (token.isEmpty) {
        usageException('Token is not provided.');
      }

      tokenStore.addToken(Token.bearer(hostedUrl, token));
      log.message('You are now logged in to $hostedUrl using bearer token.');
    } on FormatException catch (error, stackTrace) {
      log.error('Invalid or malformed server URL provided.', error, stackTrace);
    } on TimeoutException catch (error, stackTrace) {
      // Timeout is added to readLine call to make sure automated jobs doesn't
      // get stuck on noop state if user forget to pipe token to the 'token add'
      // command. This behavior might be removed..
      log.error('Timeout error. Token is not provided within 5 minutes.', error,
          stackTrace);
    }
  }
}
