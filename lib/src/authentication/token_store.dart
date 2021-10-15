// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../exceptions.dart';
import '../io.dart';
import '../log.dart' as log;
import 'credential.dart';

/// Stores and manages authentication credentials.
class TokenStore {
  TokenStore(this.configDir);

  /// Cache directory.
  final String? configDir;

  /// List of saved authentication tokens.
  ///
  /// Modifying this field will not write changes to the disk. You have to call
  /// [flush] to save changes.
  Iterable<Credential> get credentials => _loadCredentials();

  /// Reads "pub-tokens.json" and parses / deserializes it into list of
  /// [Credential].
  List<Credential> _loadCredentials() {
    final result = <Credential>[];
    final path = _tokensFile;
    if (path == null || !fileExists(path)) {
      return result;
    }

    try {
      dynamic json;
      try {
        json = jsonDecode(readTextFile(path));
      } on FormatException {
        throw FormatException('$path is not valid JSON');
      }

      if (json is! Map<String, dynamic>) {
        throw FormatException('JSON contents is corrupted or not supported');
      }
      if (json['version'] != 1) {
        throw FormatException('Version is not supported');
      }

      if (json.containsKey('hosted')) {
        final hosted = json['hosted'];

        if (hosted is! List) {
          throw FormatException('Invalid or not supported format');
        }

        for (final element in hosted) {
          try {
            if (element is! Map<String, dynamic>) {
              throw FormatException('Invalid or not supported format');
            }

            final credential = Credential.fromJson(element);
            result.add(credential);

            if (!credential.isValid()) {
              throw FormatException('Invalid or not supported credential');
            }
          } on FormatException catch (e) {
            if (element['url'] is String) {
              log.warning(
                'Failed to load credentials for ${element['url']}: '
                '${e.message}',
              );
            } else {
              log.warning(
                'Failed to load credentials for unknown hosted repository: '
                '${e.message}',
              );
            }
          }
        }
      }
    } on FormatException catch (e) {
      log.warning('Failed to load pub-tokens.json: ${e.message}');
    }

    return result;
  }

  Never missingConfigDir() {
    final variable = Platform.isWindows ? '%APPDATA%' : r'$HOME';
    throw DataException('No config dir found. Check that $variable is set');
  }

  /// Writes [credentials] into "pub-tokens.json".
  void _saveCredentials(List<Credential> credentials) {
    final tokensFile = _tokensFile;
    if (tokensFile == null) {
      missingConfigDir();
    }
    ensureDir(path.dirname(tokensFile));
    writeTextFile(
        tokensFile,
        jsonEncode(<String, dynamic>{
          'version': 1,
          'hosted': credentials.map((it) => it.toJson()).toList(),
        }));
  }

  /// Adds [token] into store and writes into disk.
  void addCredential(Credential token) {
    final _credentials = _loadCredentials();

    // Remove duplicate tokens
    _credentials.removeWhere((it) => it.url == token.url);
    _credentials.add(token);
    _saveCredentials(_credentials);
  }

  /// Removes tokens with matching [hostedUrl] from store. Returns whether or
  /// not there's a stored token with matching url.
  bool removeCredential(Uri hostedUrl) {
    final _credentials = _loadCredentials();

    var i = 0;
    var found = false;
    while (i < _credentials.length) {
      if (_credentials[i].url == hostedUrl) {
        _credentials.removeAt(i);
        found = true;
      } else {
        i++;
      }
    }

    _saveCredentials(_credentials);

    return found;
  }

  /// Returns [Credential] for authenticating given [hostedUrl] or `null` if no
  /// matching credential is found.
  Credential? findCredential(Uri hostedUrl) {
    Credential? matchedCredential;
    for (final credential in credentials) {
      if (credential.url == hostedUrl && credential.isValid()) {
        if (matchedCredential == null) {
          matchedCredential = credential;
        } else {
          log.warning(
            'Found multiple matching authentication tokens for "$hostedUrl". '
            'First matching token will be used for authentication.',
          );
          break;
        }
      }
    }

    return matchedCredential;
  }

  /// Returns whether or not store contains a token that could be used for
  /// authenticating given [url].
  bool hasCredential(Uri url) {
    return credentials.any((it) => it.url == url && it.isValid());
  }

  /// Deletes pub-tokens.json file from the disk.
  void deleteTokensFile() {
    final tokensFile = _tokensFile;
    if (tokensFile == null) {
      missingConfigDir();
    } else if (!fileExists(tokensFile)) {
      log.message('No credentials file found at "$tokensFile"');
    } else {
      deleteEntry(tokensFile);
      log.message('pub-tokens.json is deleted.');
    }
  }

  /// Full path to the "pub-tokens.json" file.
  ///
  /// `null` if no config directory could be found.
  String? get _tokensFile {
    var dir = configDir;
    return dir == null ? null : path.join(dir, 'pub-tokens.json');
  }
}
