// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import '../command.dart';
import '../exceptions.dart';
import '../exit_codes.dart' as exit_codes;
import '../http.dart';
import '../log.dart' as log;
import '../oauth2.dart' as oauth2;

/// Handles the `uploader` pub command.
class UploaderCommand extends PubCommand {
  @override
  String get name => 'uploader';
  @override
  String get description => 'Manage uploaders for a package on pub.dev.';
  @override
  String get argumentsDescription => '[options] {add/remove} <email>';
  @override
  String get docUrl => 'https://dart.dev/tools/pub/cmd/pub-uploader';

  /// The URL of the package hosting server.
  Uri get server => Uri.parse(argResults['server']);

  UploaderCommand() {
    argParser.addOption('server',
        hide: true,
        defaultsTo: cache.sources.hosted.defaultUrl,
        help: 'The package server on which the package is hosted.');
    argParser.addOption('package',
        help: 'The package whose uploaders will be modified.\n'
            '(defaults to the current package)');
  }

  @override
  Future<void> runProtected() async {
    if (argResults.rest.isEmpty) {
      log.error('No uploader command given.');
      printUsage();
      throw ExitWithException(exit_codes.USAGE);
    }

    var rest = argResults.rest.toList();

    // TODO(rnystrom): Use subcommands for these.
    var command = rest.removeAt(0);
    if (!['add', 'remove'].contains(command)) {
      log.error('Unknown uploader command "$command".');
      printUsage();
      throw ExitWithException(exit_codes.USAGE);
    } else if (rest.isEmpty) {
      log.error('No uploader given for "pub uploader $command".');
      printUsage();
      throw ExitWithException(exit_codes.USAGE);
    }

    final package = argResults['package'] ?? entrypoint.root.name;
    final uploader = rest[0];
    try {
      final response = await oauth2.withClient(cache, (client) {
        if (command == 'add') {
          var url = server.resolve('/api/packages/'
              '${Uri.encodeComponent(package)}/uploaders');
          return client
              .post(url, headers: pubApiHeaders, body: {'email': uploader});
        } else {
          // command == 'remove'
          var url = server.resolve('/api/packages/'
              '${Uri.encodeComponent(package)}/uploaders/'
              '${Uri.encodeComponent(uploader)}');
          return client.delete(url, headers: pubApiHeaders);
        }
      });
      handleJsonSuccess(response);
    } on PubHttpException catch (error) {
      handleJsonError(error.response);
    }
  }
}
