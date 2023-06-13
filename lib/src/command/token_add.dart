// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import '../authentication/credential.dart';
import '../command.dart';
import '../command_runner.dart';
import '../exceptions.dart';
import '../io.dart';
import '../log.dart' as log;
import '../source/hosted.dart';
import '../utils.dart';

/// Handles the `token add` pub command.
class TokenAddCommand extends PubCommand {
  @override
  String get name => 'add';
  @override
  String get description => '''
Add an authentication token for a package repository.

The token will be used for authorizing against <hosted-url> both when
retrieving dependencies and for publishing.

Tokens are stored in ${tokenStore.tokensFile}.

This command will prompt for the secret token over stdin.
(Unless `--env-var` is used).

For interactive authorization against pub.dev, use `$topLevelProgram pub login`.''';
  @override
  String get argumentsDescription => '[options] <hosted-url>';

  @override
  String get docUrl => 'https://dart.dev/tools/pub/cmd/pub-token';

  String? get envVar => argResults['env-var'] as String?;

  TokenAddCommand() {
    argParser.addOption(
      'env-var',
      help: 'Read the secret token from this environment variable when '
          'making requests.',
      valueHelp: 'VARIABLE',
    );
  }

  @override
  Future<void> runProtected() async {
    if (argResults.rest.isEmpty) {
      usageException(
        'The [hosted-url] for a package repository must be given.',
      );
    } else if (argResults.rest.length > 1) {
      usageException('Takes only a single argument.');
    }
    final rawHostedUrl = argResults.rest.first;

    try {
      var hostedUrl = validateAndNormalizeHostedUrl(rawHostedUrl);
      var isLocalhost =
          ['localhost', '127.0.0.1', '::1'].contains(hostedUrl.host);
      if (!hostedUrl.isScheme('HTTPS') && !isLocalhost) {
        throw FormatException('url must be https://, '
            'insecure repositories cannot use authentication.');
      }

      if (envVar == null) {
        await _addTokenFromStdin(hostedUrl);
      } else {
        await _addEnvVarToken(hostedUrl, envVar!);
      }
    } on FormatException catch (e) {
      usageException('Invalid [hosted-url]: "$rawHostedUrl"\n'
          '${e.message}');
    }
  }

  Future<void> _addTokenFromStdin(Uri hostedUrl) async {
    final token = await stdinPrompt('Enter secret token:', echoMode: false);
    if (token.isEmpty) {
      usageException('Token is not provided.');
    }

    if (!Credential.isValidBearerToken(token)) {
      dataError('The entered token is not a valid Bearer token. '
          'A token may only contain `a-zA-Z0-9._~+/=-`');
    }

    tokenStore.addCredential(Credential.token(hostedUrl, token));
    log.message(
      'Requests to "$hostedUrl" will now be authenticated using the secret '
      'token.',
    );
  }

  Future<void> _addEnvVarToken(Uri hostedUrl, String envVar) async {
    if (envVar.isEmpty) {
      usageException('Cannot use the empty string as --env-var');
    }

    // Environment variable names on Windows [1] and UNIX [2] cannot contain
    // equal signs.
    // [1] https://docs.microsoft.com/en-us/windows/win32/procthread/environment-variables
    // [2] https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap08.html
    if (envVar.contains('=')) {
      throw DataException(
        'Environment variable name --env-var="$envVar" cannot contain "=", the '
        'equals sign is not allowed in environment variable names.',
      );
    }

    // Help the user if they typed something that is unlikely to be correct.
    // This could happen if you include $, whitespace, quotes or accidentally
    // dereference the environment variable instead.
    if (!RegExp(r'^[A-Z_][A-Z0-9_]*$').hasMatch(envVar)) {
      log.warning(
        'The environment variable name --env-var="$envVar" does not use '
        'uppercase characters A-Z, 0-9 and underscore. This is unusual for '
        'environment variable names.\n'
        'Check that you meant to use the environment variable name: "$envVar".',
      );
    }

    tokenStore.addCredential(Credential.env(hostedUrl, envVar));
    log.message(
      'Requests to "$hostedUrl" will now be authenticated using the secret '
      'token stored in the environment variable "$envVar".',
    );

    if (!Platform.environment.containsKey(envVar)) {
      // If environment variable doesn't exist when
      // pub token add <hosted-url> --env-var <ENV_VAR> is called, we should
      // print a warning.
      log.warning('Environment variable "$envVar" is not defined.');
    }
  }
}
