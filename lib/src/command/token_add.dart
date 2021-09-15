// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart=2.11

import 'dart:async';

import '../authentication/credential.dart';
import '../command.dart';
import '../exceptions.dart';
import '../io.dart';
import '../log.dart' as log;
import '../source/hosted.dart';

/// Handles the `token add` pub command.
class TokenAddCommand extends PubCommand {
  @override
  String get name => 'add';
  @override
  String get description =>
      'Add authentication tokens for a package repository.';
  @override
  String get invocation => 'pub token add';
  @override
  String get argumentsDescription => '[hosted-url]';

  @override
  Future<void> runProtected() async {
    if (argResults.rest.isEmpty) {
      usageException(
          'The [hosted-url] for a package repository must be given.');
    } else if (argResults.rest.length > 1) {
      usageException('Takes only a single argument.');
    }

    try {
      var hostedUrl = validateAndNormalizeHostedUrl(argResults.rest.first);
      if (hostedUrl.isScheme('HTTP')) {
        throw DataException('Insecure package repository could not be added.');
      }

      final token = await stdinPrompt('Enter secret token:', echoMode: false)
          .timeout(const Duration(minutes: 15));
      if (token.isEmpty) {
        usageException('Token is not provided.');
      }

      tokenStore.addCredential(Credential.token(hostedUrl, token));
      log.message(
        'Requests to $hostedUrl will now be authenticated using the secret '
        'token.',
      );
    } on FormatException catch (e) {
      usageException('Invalid [hosted-url]: "${argResults.rest.first}"\n'
          '${e.message}');
    } on TimeoutException catch (_) {
      // Timeout is added to readLine call to make sure automated jobs doesn't
      // get stuck on noop state if user forget to pipe token to the 'token add'
      // command. This behavior might be removed.
      throw ApplicationException('Token is not provided within 15 minutes.');
    }
  }
}
