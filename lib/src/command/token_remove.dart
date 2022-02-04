// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../command.dart';
import '../exceptions.dart';
import '../log.dart' as log;
import '../source/hosted.dart';

/// Handles the `token remove` pub command.
class TokenRemoveCommand extends PubCommand {
  @override
  String get name => 'remove';
  @override
  String get description => 'Remove secret token for package repository.';
  @override
  String get invocation => 'pub token remove';
  @override
  String get argumentsDescription => '[hosted-url]';

  bool get isAll => argResults['all'];

  TokenRemoveCommand() {
    argParser.addFlag(
      'all',
      negatable: false,
      help: 'Remove all secret tokens.',
    );
  }

  @override
  Future<void> runProtected() async {
    if (isAll) {
      final count = tokenStore.credentials.length;
      tokenStore.deleteTokensFile();
      log.message('Removed $count secret tokens.');
      return;
    }

    if (argResults.rest.isEmpty) {
      usageException(
          'The [hosted-url] for a package repository must be specified.');
    } else if (argResults.rest.length > 1) {
      usageException('Takes only a single argument.');
    }

    try {
      final hostedUrl = validateAndNormalizeHostedUrl(argResults.rest.first);
      final found = tokenStore.removeCredential(hostedUrl);

      if (found) {
        log.message('Removed secret token for package repository: $hostedUrl');
      } else {
        throw DataException(
            'No secret token for package repository "$hostedUrl" was found.');
      }
    } on FormatException catch (e) {
      usageException('Invalid [hosted-url]: "${argResults.rest.first}"\n'
          '${e.message}');
    }
  }
}
