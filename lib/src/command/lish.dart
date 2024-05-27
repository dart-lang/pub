// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../ascii_tree.dart' as tree;
import '../authentication/client.dart';
import '../command.dart';
import '../command_runner.dart';
import '../exceptions.dart' show DataException;
import '../exit_codes.dart';
import '../http.dart';
import '../io.dart';
import '../log.dart' as log;
import '../oauth2.dart' as oauth2;
import '../pubspec.dart';
import '../solver/type.dart';
import '../source/hosted.dart' show validateAndNormalizeHostedUrl;
import '../source/root.dart';
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
  Uri computeHost(Pubspec pubspec) {
    // An explicit argument takes precedence.
    if (argResults.wasParsed('server')) {
      try {
        return validateAndNormalizeHostedUrl(
          argResults.optionWithDefault('server'),
        );
      } on FormatException catch (e) {
        usageException('Invalid server: $e');
      }
    }

    // Otherwise, use the one specified in the pubspec.
    final publishTo = pubspec.publishTo;
    if (publishTo != null && publishTo != 'none') {
      try {
        return validateAndNormalizeHostedUrl(publishTo);
      } on FormatException catch (e) {
        throw DataException('Invalid publish_to: $e');
      }
    }

    // Use the default server if nothing else is specified
    return Uri.parse(cache.hosted.defaultUrl);
  }

  /// Whether the publish is just a preview.
  bool get dryRun => argResults.flag('dry-run');

  /// Whether the publish requires confirmation.
  bool get force => argResults.flag('force');

  bool get skipValidation => argResults.flag('skip-validation');

  late final String? _fromArchive = argResults.option('from-archive');
  late final String? _toArchive = argResults.option('to-archive');

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
      'to-archive',
      help: 'Create a .tar.gz archive instead of publishing to server',
      valueHelp: '[archive.tar.gz]',
      hide: true,
    );
    argParser.addOption(
      'from-archive',
      help:
          'Publish from a .tar.gz archive instead of current folder. Implies `--skip-validation`.',
      valueHelp: '[archive.tar.gz]',
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
    Uri host,
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
        final url = _expectField(parameters, 'url', parametersResponse);
        if (url is! String) invalidServerResponse(parametersResponse);
        cloudStorageUrl = Uri.parse(url);
        final uploadResponse =
            await retryForHttp('uploading package', () async {
          // TODO(nweiz): Cloud Storage can provide an XML-formatted error. We
          // should report that error and exit.
          final request = http.MultipartRequest('POST', cloudStorageUrl!);

          final fields = _expectField(parameters, 'fields', parametersResponse);
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
        final location = uploadResponse.headers['location'];
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
      final url = error.response.request!.url;
      if (url == cloudStorageUrl) {
        handleGCSError(error.response);
        fail(log.red('Failed to upload the package.'));
      } else if (Uri.parse(url.origin) == Uri.parse(host.origin)) {
        handleJsonError(error.response);
      } else {
        rethrow;
      }
    }
  }

  Future<void> _publish(List<int> packageBytes, Uri host) async {
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
          return _publishUsingClient(packageBytes, client, host);
        });
      } else {
        // For third party servers using bearer authentication client
        await withAuthenticatedClient(cache, host, (client) {
          return _publishUsingClient(packageBytes, client, host);
        });
      }
    } on PubHttpResponseException catch (error) {
      final url = error.response.request!.url;
      if (Uri.parse(url.origin) == Uri.parse(host.origin)) {
        handleJsonError(error.response);
      } else {
        rethrow;
      }
    }
  }

  Future<void> _validateArgs() async {
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

    if (_fromArchive != null && _toArchive != null) {
      usageException('Cannot use both --from-archive and --to-archive.');
    }

    if (_fromArchive != null && dryRun) {
      usageException('Cannot use both --from-archive and --dry-run.');
    }

    if (_toArchive != null && force) {
      usageException('Cannot use both --to-archive and --force.');
    }
  }

  Future<_Publication> _publicationFromEntrypoint() async {
    if (!dryRun &&
        _toArchive == null &&
        entrypoint.workPackage.pubspec.isPrivate) {
      dataError('A private package cannot be published.\n'
          'You can enable this by changing the "publish_to" field in your '
          'pubspec.');
    }
    if (skipValidation) {
      log.warning(
        'Running with `skip-validation`. No client-side validation is done.',
      );
    } else {
      await entrypoint.acquireDependencies(SolveType.get);
    }

    // For displaying the layout we only want to explicitly mention non-empty
    // directories, so first we list all files and directories, and then filter
    // any non-empty directories away.
    // For validation it is practical to also maintain the list of files.
    final filesAndDirs = entrypoint.workPackage.listFiles(includeDirs: true);

    final files = <String>[];
    final filesAndEmptyDirs = <String>[];
    for (final entry in filesAndDirs) {
      final stat = statPath(entry);
      if (stat.type == FileSystemEntityType.directory) {
        if (listDir(entry).isEmpty) {
          filesAndEmptyDirs.add(entry);
        }
      } else {
        files.add(entry);
        filesAndEmptyDirs.add(entry);
      }
    }

    log.fine('Archiving and publishing ${entrypoint.workPackage.name}.');

    // Show the package contents so the user can verify they look OK.
    final package = entrypoint.workPackage;
    final host = computeHost(package.pubspec);
    log.message(
      'Publishing ${package.name} ${package.version} to $host:\n'
      '${tree.fromFiles(filesAndEmptyDirs, baseDir: entrypoint.workPackage.dir, showFileSizes: true)}',
    );

    final packageBytes = await createTarGz(
      filesAndDirs,
      baseDir: entrypoint.workPackage.dir,
    ).toBytes();

    log.message(
      '\nTotal compressed archive size: ${_readableFileSize(packageBytes.length)}.\n',
    );

    final validationResult =
        skipValidation ? null : await _validate(packageBytes, files, host);

    if (dryRun) {
      log.message('The server may enforce additional checks.');
    }
    return _Publication(
      packageBytes: packageBytes,
      warningCount: validationResult?.warningsCount ?? 0,
      hintCount: validationResult?.hintsCount ?? 0,
      pubspec: package.pubspec,
    );
  }

  Future<_Publication> _publicationFromArchive(String archive) async {
    final Uint8List packageBytes;
    try {
      log.message('Publishing from archive: $_fromArchive');

      packageBytes = readBinaryFile(archive);
    } on FileSystemException catch (e) {
      dataError(
        'Failed reading archive file: $e)',
      );
    }
    final Pubspec pubspec;
    try {
      pubspec = Pubspec.parse(
        utf8.decode(
          await extractFileFromTarGz(
            Stream.fromIterable([packageBytes]),
            'pubspec.yaml',
          ),
        ),
        cache.sources,
        containingDescription: RootDescription(p.dirname(archive)),
      );
    } on FormatException catch (e) {
      dataError('Failed to read pubspec.yaml from archive: ${e.message}');
    }
    if (!dryRun && _toArchive == null && pubspec.isPrivate) {
      dataError('A private package cannot be published.\n'
          'You can enable this by changing the "publish_to" field in your '
          'pubspec.');
    }
    final host = computeHost(pubspec);
    log.message('Publishing ${pubspec.name} ${pubspec.version} to $host.');
    return _Publication(
      packageBytes: packageBytes,
      warningCount: 0,
      hintCount: 0,
      pubspec: pubspec,
    );
  }

  /// Validates the package.
  ///
  /// Throws if there are errors and the upload should not
  /// proceed.
  ///
  /// Returns a summary of warnings and hints if there are any, otherwise `null`.
  Future<({int warningsCount, int hintsCount})> _validate(
    Uint8List packageBytes,
    List<String> files,
    Uri host,
  ) async {
    final hints = <String>[];
    final warnings = <String>[];
    final errors = <String>[];

    await log.spinner(
      'Validating package',
      () async => await Validator.runAll(
        entrypoint,
        packageBytes.length,
        host,
        files,
        hints: hints,
        warnings: warnings,
        errors: errors,
      ),
    );

    if (errors.isNotEmpty) {
      dataError('Sorry, your package is missing '
          "${(errors.length > 1) ? 'some requirements' : 'a requirement'} "
          "and can't be published yet.\nFor more information, see: "
          'https://dart.dev/tools/pub/cmd/pub-lish.\n');
    }

    return (warningsCount: warnings.length, hintsCount: hints.length);
  }

  /// Asks the user for confirmation of uploading [package].
  ///
  /// Skips asking if [force].
  /// Throws if user didn't confirm.
  Future<void> _confirmUpload(_Publication package, Uri host) async {
    if (force) return;
    log.message('\nPublishing is forever; packages cannot be unpublished.'
        '\nPolicy details are available at https://pub.dev/policy\n');

    var message =
        'Do you want to publish ${package.pubspec.name} ${package.pubspec.version} to $host';
    if (package.hintCount != 0 || package.warningCount != 0) {
      message = '${package.warningsCountMessage}. $message';
    }
    if (!await confirm('\n$message')) {
      dataError('Package upload canceled.');
    }
  }

  @override
  Future runProtected() async {
    await _validateArgs();
    final publication = await (_fromArchive == null
        ? _publicationFromEntrypoint()
        : _publicationFromArchive(_fromArchive));
    if (dryRun) {
      log.warning(publication.warningsCountMessage);
      if (publication.warningCount != 0) {
        overrideExitCode(DATA);
      }
      return;
    }
    if (_toArchive == null) {
      final host = computeHost(publication.pubspec);
      await _confirmUpload(publication, host);

      await _publish(publication.packageBytes, host);
    } else {
      if (dryRun) {
        log.message('Would have written to $_toArchive.');
      } else {
        _writeUploadToArchive(publication, _toArchive);
      }
    }
  }

  void _writeUploadToArchive(_Publication publication, String archive) {
    try {
      writeBinaryFile(archive, publication.packageBytes);
    } on FileSystemException catch (e) {
      dataError('Failed writing archive: $e');
    }
    log.message('Wrote package archive at $_toArchive');
  }

  /// Returns the value associated with [key] in [map]. Throws a user-friendly
  /// error if [map] doesn't contain [key].
  dynamic _expectField(Map map, String key, http.Response response) {
    if (map.containsKey(key)) return map[key];
    invalidServerResponse(response);
  }
}

String _readableFileSize(int size) {
  if (size >= 1 << 30) {
    return '${size ~/ (1 << 30)} GB';
  } else if (size >= 1 << 20) {
    return '${size ~/ (1 << 20)} MB';
  } else if (size >= 1 << 10) {
    return '${size ~/ (1 << 10)} KB';
  } else {
    return '<1 KB';
  }
}

class _Publication {
  Uint8List packageBytes;
  int warningCount;
  int hintCount;

  Pubspec pubspec;

  String get warningsCountMessage {
    final hintText =
        hintCount == 0 ? '' : ' and $hintCount ${pluralize('hint', hintCount)}';
    return '\nPackage has $warningCount '
        '${pluralize('warning', warningCount)}$hintText.';
  }

  _Publication({
    required this.packageBytes,
    required this.warningCount,
    required this.hintCount,
    required this.pubspec,
  });
}
