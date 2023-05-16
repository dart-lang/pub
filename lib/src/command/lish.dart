// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../ascii_tree.dart' as tree;
import '../authentication/client.dart';
import '../command.dart';
import '../command_runner.dart';
import '../exceptions.dart' show DataException;
import '../exit_codes.dart' as exit_codes;
import '../http.dart';
import '../io.dart';
import '../log.dart' as log;
import '../oauth2.dart' as oauth2;
import '../solver/type.dart';
import '../source/hosted.dart' show validateAndNormalizeHostedUrl;
import '../utils.dart';
import '../validator.dart';

/// Handles the `lish` and `publish` pub commands.
class LishCommand extends PubCommand {
  @override
  String get name => 'publish';
  @override
  String get description => 'Publish the current package to pub.dev.';
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
        return validateAndNormalizeHostedUrl(asString(argResults['server']));
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
  bool get dryRun => asBool(argResults['dry-run']);

  /// Whether the publish requires confirmation.
  bool get force => asBool(argResults['force']);

  bool get skipValidation => asBool(argResults['skip-validation']);

  LishCommand() {
    argParser.addFlag(
      'dry-run',
      abbr: 'n',
      negatable: false,
      help: 'Validate but do not publish the package.',
    );
    argParser.addFlag(
      'force',
      abbr: 'f',
      negatable: false,
      help: 'Publish without confirmation if there are no errors.',
    );
    argParser.addFlag(
      'skip-validation',
      negatable: false,
      help:
          'Publish without validation and resolution (this will ignore errors).',
    );
    argParser.addOption(
      'server',
      help: 'The package server to which to upload this package.',
      hide: true,
    );

    argParser.addOption(
      'directory',
      abbr: 'C',
      help: 'Run this in the directory <dir>.',
      valueHelp: 'dir',
    );
  }

  Future<void> _publishUsingClient(
    List<int> packageBytes,
    http.Client client,
  ) async {
    Uri? cloudStorageUrl;

    try {
      await log.progress('Uploading', () async {
        /// 1. Initiate upload
        final parametersResponse =
            await retryForHttp('initiating upload', () async {
          final request =
              http.Request('GET', host.resolve('api/packages/versions/new'));
          request.attachPubApiHeaders();
          request.attachMetadataHeaders();
          return await client.fetch(request);
        });
        final parameters = parseJsonResponse(parametersResponse);

        /// 2. Upload package
        var url = _expectField(parameters, 'url', parametersResponse);
        if (url is! String) invalidServerResponse(parametersResponse);
        cloudStorageUrl = Uri.parse(url);
        final uploadResponse =
            await retryForHttp('uploading package', () async {
          // TODO(nweiz): Cloud Storage can provide an XML-formatted error. We
          // should report that error and exit.
          var request = http.MultipartRequest('POST', cloudStorageUrl!);

          var fields = _expectField(parameters, 'fields', parametersResponse);
          if (fields is! Map) invalidServerResponse(parametersResponse);
          fields.forEach((key, value) {
            if (value is! String) invalidServerResponse(parametersResponse);
            request.fields[key as String] = value;
          });

          request.followRedirects = false;
          request.files.add(
            http.MultipartFile.fromBytes(
              'file',
              packageBytes,
              filename: 'package.tar.gz',
            ),
          );
          return await client.fetch(request);
        });

        /// 3. Finalize publish
        var location = uploadResponse.headers['location'];
        if (location == null) throw PubHttpResponseException(uploadResponse);
        final finalizeResponse =
            await retryForHttp('finalizing publish', () async {
          final request = http.Request('GET', Uri.parse(location));
          request.attachPubApiHeaders();
          request.attachMetadataHeaders();
          return await client.fetch(request);
        });
        handleJsonSuccess(finalizeResponse);
      });
    } on AuthenticationException catch (error) {
      var msg = '';
      if (error.statusCode == 401) {
        msg += '$host package repository requested authentication!\n'
            'You can provide credentials using:\n'
            '    $topLevelProgram pub token add $host\n';
      }
      if (error.statusCode == 403) {
        msg += 'Insufficient permissions to the resource at the $host '
            'package repository.\nYou can modify credentials using:\n'
            '    $topLevelProgram pub token add $host\n';
      }
      if (error.serverMessage != null) {
        msg += '\n${error.serverMessage!}\n';
      }
      dataError(msg + log.red('Authentication failed!'));
    } on PubHttpResponseException catch (error) {
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
        'https://pub.dev',
        // [validateAndNormalizeHostedUrl] normalizes https://pub.dartlang.org
        // to https://pub.dev, so we don't need to do allow that here.

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
      final isOfficialServer = officialPubServers.contains(host.toString());
      if (isOfficialServer && !cache.tokenStore.hasCredential(host)) {
        // Using OAuth2 authentication client for the official pub servers, when
        // we don't have an explicit token from [TokenStore] to use instead.
        //
        // This allows us to use `dart pub token add` to inject a token for use
        // with the official servers.
        await oauth2.withClient((client) {
          return _publishUsingClient(packageBytes, client);
        });
      } else {
        // For third party servers using bearer authentication client
        await withAuthenticatedClient(cache, host, (client) {
          return _publishUsingClient(packageBytes, client);
        });
      }
    } on PubHttpResponseException catch (error) {
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
      await log.errorsOnlyUnlessTerminal(() {
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

    if (!skipValidation) {
      await entrypoint.acquireDependencies(SolveType.get, analytics: analytics);
    } else {
      log.warning(
        'Running with `skip-validation`. No client-side validation is done.',
      );
    }

    var files = entrypoint.root.listFiles();
    log.fine('Archiving and publishing ${entrypoint.root.name}.');

    // Show the package contents so the user can verify they look OK.
    var package = entrypoint.root;
    log.message(
      'Publishing ${package.name} ${package.version} to $host:\n'
      '${tree.fromFiles(files, baseDir: entrypoint.rootDir, showFileSizes: true)}',
    );

    var packageBytesFuture =
        createTarGz(files, baseDir: entrypoint.rootDir).toBytes();

    // Validate the package.
    var isValid = skipValidation
        ? true
        : await _validate(
            packageBytesFuture.then((bytes) => bytes.length),
            files,
          );
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

    await log.spinner(
      'Validating package',
      () async => await Validator.runAll(
        entrypoint,
        packageSize,
        host,
        files,
        hints: hints,
        warnings: warnings,
        errors: errors,
      ),
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
      final hintText = hints.isEmpty
          ? ''
          : ' and ${hints.length} ${pluralize('hint', hints.length)}';
      return '\nPackage has ${warnings.length} '
          '${pluralize('warning', warnings.length)}$hintText.';
    }

    if (dryRun) {
      log.warning(formatWarningCount());
      return warnings.isEmpty;
    }

    log.message('\nPublishing is forever; packages cannot be unpublished.'
        '\nPolicy details are available at https://pub.dev/policy');

    final package = entrypoint.root;
    var message =
        'Do you want to publish ${package.name} ${package.version} to $host';

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
