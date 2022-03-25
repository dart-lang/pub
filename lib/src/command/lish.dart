// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../ascii_tree.dart' as tree;
import '../authentication/client.dart';
import '../command.dart';
import '../exceptions.dart' show DataException;
import '../exit_codes.dart' as exit_codes;
import '../http.dart';
import '../io.dart';
import '../log.dart' as log;
import '../oauth2.dart' as oauth2;
import '../source/hosted.dart' show validateAndNormalizeHostedUrl;
import '../utils.dart';
import '../validator.dart';

/// Handles the `lish` and `publish` pub commands.
class LishCommand extends PubCommand {
  @override
  String get name => 'publish';
  @override
  String get description => 'Publish the current package to pub.dartlang.org.';
  @override
  String get argumentsDescription => '[options]';
  @override
  String get docUrl => 'https://dart.dev/tools/pub/cmd/pub-lish';
  @override
  bool get takesArguments => false;

  /// The URL of the server to which to upload the package.
  late final Uri host = () {
    // An explicit argument takes precedence.
    if (argResults.wasParsed('server')) {
      try {
        return validateAndNormalizeHostedUrl(argResults['server']);
      } on FormatException catch (e) {
        usageException('Invalid server: $e');
      }
    }

    // Otherwise, use the one specified in the pubspec.
    final publishTo = entrypoint.root.pubspec.publishTo;
    if (publishTo != null) {
      try {
        return validateAndNormalizeHostedUrl(publishTo);
      } on FormatException catch (e) {
        throw DataException('Invalid publish_to: $e');
      }
    }

    // Use the default server if nothing else is specified
    return Uri.parse(cache.hosted.defaultUrl);
  }();

  /// Whether the publish is just a preview.
  bool get dryRun => argResults['dry-run'];

  /// Whether the publish requires confirmation.
  bool get force => argResults['force'];

  LishCommand() {
    argParser.addFlag('dry-run',
        abbr: 'n',
        negatable: false,
        help: 'Validate but do not publish the package.');
    argParser.addFlag('force',
        abbr: 'f',
        negatable: false,
        help: 'Publish without confirmation if there are no errors.');
    argParser.addOption('server',
        help: 'The package server to which to upload this package.',
        hide: true);

    argParser.addOption('directory',
        abbr: 'C', help: 'Run this in the directory<dir>.', valueHelp: 'dir');
  }

  Future<void> _publishUsingClient(
    List<int> packageBytes,
    http.Client client,
  ) async {
    Uri? cloudStorageUrl;

    try {
      await log.progress('Uploading', () async {
        var newUri = host.resolve('api/packages/versions/new');
        var response = await client.get(newUri, headers: pubApiHeaders);
        var parameters = parseJsonResponse(response);

        var url = _expectField(parameters, 'url', response);
        if (url is! String) invalidServerResponse(response);
        cloudStorageUrl = Uri.parse(url);
        // TODO(nweiz): Cloud Storage can provide an XML-formatted error. We
        // should report that error and exit.
        var request = http.MultipartRequest('POST', cloudStorageUrl!);

        var fields = _expectField(parameters, 'fields', response);
        if (fields is! Map) invalidServerResponse(response);
        fields.forEach((key, value) {
          if (value is! String) invalidServerResponse(response);
          request.fields[key] = value;
        });

        request.followRedirects = false;
        request.files.add(http.MultipartFile.fromBytes('file', packageBytes,
            filename: 'package.tar.gz'));
        var postResponse =
            await http.Response.fromStream(await client.send(request));

        var location = postResponse.headers['location'];
        if (location == null) throw PubHttpException(postResponse);
        handleJsonSuccess(
            await client.get(Uri.parse(location), headers: pubApiHeaders));
      });
    } on AuthenticationException catch (error) {
      var msg = '';
      if (error.statusCode == 401) {
        msg += '$host package repository requested authentication!\n'
            'You can provide credentials using:\n'
            '    pub token add $host\n';
      }
      if (error.statusCode == 403) {
        msg += 'Insufficient permissions to the resource at the $host '
            'package repository.\nYou can modify credentials using:\n'
            '    pub token add $host\n';
      }
      if (error.serverMessage != null) {
        msg += '\n' + error.serverMessage! + '\n';
      }
      dataError(msg + log.red('Authentication failed!'));
    } on PubHttpException catch (error) {
      var url = error.response.request!.url;
      if (url == cloudStorageUrl) {
        // TODO(nweiz): the response may have XML-formatted information about
        // the error. Try to parse that out once we have an easily-accessible
        // XML parser.
        fail(log.red('Failed to upload the package.'));
      } else if (Uri.parse(url.origin) == Uri.parse(host.origin)) {
        handleJsonError(error.response);
      } else {
        rethrow;
      }
    }
  }

  Future<void> _publish(List<int> packageBytes) async {
    try {
      final officialPubServers = {
        'https://pub.dartlang.org',
        // [validateAndNormalizeHostedUrl] normalizes https://pub.dev to
        // https://pub.dartlang.org, so we don't need to do allow that here.

        // Pub uses oauth2 credentials only for authenticating official pub
        // servers for security purposes (to not expose pub.dev access token to
        // 3rd party servers).
        // For testing publish command we're using mock servers hosted on
        // localhost address which is not a known pub server address. So we
        // explicitly have to define mock servers as official server to test
        // publish command with oauth2 credentials.
        if (runningFromTest &&
            Platform.environment.containsKey('_PUB_TEST_DEFAULT_HOSTED_URL'))
          Platform.environment['_PUB_TEST_DEFAULT_HOSTED_URL'],
      };

      // Using OAuth2 authentication client for the official pub servers
      final isOfficalServer = officialPubServers.contains(host.toString());
      if (isOfficalServer && !cache.tokenStore.hasCredential(host)) {
        // Using OAuth2 authentication client for the official pub servers, when
        // we don't have an explicit token from [TokenStore] to use instead.
        //
        // This allows us to use `dart pub token add` to inject a token for use
        // with the official servers.
        await oauth2.withClient(cache, (client) {
          return _publishUsingClient(packageBytes, client);
        });
      } else {
        // For third party servers using bearer authentication client
        await withAuthenticatedClient(cache, host, (client) {
          return _publishUsingClient(packageBytes, client);
        });
      }
    } on PubHttpException catch (error) {
      var url = error.response.request!.url;
      if (Uri.parse(url.origin) == Uri.parse(host.origin)) {
        handleJsonError(error.response);
      } else {
        rethrow;
      }
    }
  }

  @override
  Future runProtected() async {
    if (argResults.wasParsed('server')) {
      await log.warningsOnlyUnlessTerminal(() {
        log.message(
          '''
The --server option is deprecated. Use `publish_to` in your pubspec.yaml or set
the \$PUB_HOSTED_URL environment variable.''',
        );
      });
    }

    if (force && dryRun) {
      usageException('Cannot use both --force and --dry-run.');
    }

    if (entrypoint.root.pubspec.isPrivate) {
      dataError('A private package cannot be published.\n'
          'You can enable this by changing the "publish_to" field in your '
          'pubspec.');
    }

    var files = entrypoint.root.listFiles();
    log.fine('Archiving and publishing ${entrypoint.root.name}.');

    // Show the package contents so the user can verify they look OK.
    var package = entrypoint.root;
    log.message('Publishing ${package.name} ${package.version} to $host:\n'
        '${tree.fromFiles(files, baseDir: entrypoint.root.dir)}');

    var packageBytesFuture =
        createTarGz(files, baseDir: entrypoint.root.dir).toBytes();

    // Validate the package.
    var isValid = await _validate(
        packageBytesFuture.then((bytes) => bytes.length), files);
    if (!isValid) {
      overrideExitCode(exit_codes.DATA);
      return;
    } else if (dryRun) {
      log.message('The server may enforce additional checks.');
      return;
    } else {
      await _publish(await packageBytesFuture);
    }
  }

  /// Returns the value associated with [key] in [map]. Throws a user-friendly
  /// error if [map] doesn't contain [key].
  dynamic _expectField(Map map, String key, http.Response response) {
    if (map.containsKey(key)) return map[key];
    invalidServerResponse(response);
  }

  /// Validates the package. Completes to false if the upload should not
  /// proceed.
  Future<bool> _validate(Future<int> packageSize, List<String> files) async {
    final hints = <String>[];
    final warnings = <String>[];
    final errors = <String>[];

    await Validator.runAll(
      entrypoint,
      packageSize,
      host,
      files,
      hints: hints,
      warnings: warnings,
      errors: errors,
    );

    if (errors.isNotEmpty) {
      log.error('Sorry, your package is missing '
          "${(errors.length > 1) ? 'some requirements' : 'a requirement'} "
          "and can't be published yet.\nFor more information, see: "
          'https://dart.dev/tools/pub/cmd/pub-lish.\n');
      return false;
    }

    if (force) return true;

    String formatWarningCount() {
      final hs = hints.length == 1 ? '' : 's';
      final hintText = hints.isEmpty ? '' : ' and ${hints.length} hint$hs.';
      final ws = warnings.length == 1 ? '' : 's';
      return '\nPackage has ${warnings.length} warning$ws$hintText.';
    }

    if (dryRun) {
      log.warning(formatWarningCount());
      return warnings.isEmpty;
    }

    log.message('\nPublishing is forever; packages cannot be unpublished.'
        '\nPolicy details are available at https://pub.dev/policy');

    final package = entrypoint.root;
    var message = 'Do you want to publish ${package.name} ${package.version}';

    if (warnings.isNotEmpty || hints.isNotEmpty) {
      final warning = formatWarningCount();
      message = '${log.bold(log.red(warning))}. $message';
    }

    var confirmed = await confirm('\n$message');
    if (!confirmed) {
      log.error('Package upload canceled.');
      return false;
    }
    return true;
  }
}
