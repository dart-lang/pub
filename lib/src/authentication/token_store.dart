// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: import_of_legacy_library_into_null_safe

import 'dart:convert';

import 'package:path/path.dart' as path;

import '../io.dart';
import '../log.dart' as log;
import 'credential.dart';

/// Stores and manages authentication credentials.
class TokenStore {
  TokenStore(this.cacheRootDir);

  /// Cache directory.
  final String cacheRootDir;

  /// Cached list of [Credential]s.
  List<Credential>? _credentials;

  /// List of saved authentication tokens.
  ///
  /// Modifying this field will not write changes to the disk. You have to call
  /// [flush] to save changes.
  List<Credential> get credentials => _credentials ??= _loadCredentials();

  /// Reads "tokens.json" and parses / deserializes it into list of
  /// [Credential].
  List<Credential> _loadCredentials() {
    final result = List<Credential>.empty(growable: true);
    final path = _tokensFile;
    if (!fileExists(path)) {
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

            result.add(Credential.fromJson(element));
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
      log.warning('Failed to load tokens.json: ${e.message}');
    }

    return result;
  }

  /// Writes [tokens] into "tokens.json".
  void _saveTokens(List<Credential> tokens) {
    writeTextFile(
        _tokensFile,
        jsonEncode(<String, dynamic>{
          'version': 1,
          'hosted': tokens.map((it) => it.toJson()).toList(),
        }));
  }

  /// Writes latest state of the store to disk.
  void flush() {
    if (_credentials == null) {
      throw Exception('Credentials should be loaded before saving.');
    }
    _saveTokens(_credentials!);
  }

  /// Adds [token] into store and writes into disk.
  void addCredential(Credential token) {
    // Remove duplicate tokens
    credentials.removeWhere((it) => it.url == token.url);
    credentials.add(token);
    flush();
  }

  /// Removes tokens with matching [hostedUrl] from store. Returns whether or
  /// not there's a stored token with matching url.
  bool removeCredential(Uri hostedUrl) {
    var i = 0;
    var found = false;
    while (i < credentials.length) {
      if (credentials[i].url == hostedUrl) {
        credentials.removeAt(i);
        found = true;
      } else {
        i++;
      }
    }

    flush();

    return found;
  }

  /// Returns [Credential] for authenticating given url or null if no matching token
  /// is found.
  Credential? findCredential(Uri url) {
    Credential? matchedToken;
    for (final token in credentials) {
      if (token.url == url) {
        if (matchedToken == null) {
          matchedToken = token;
        } else {
          log.warning(
            'Found multiple matching authentication tokens for "$url". '
            'First matching token will be used for authentication.',
          );
          break;
        }
      }
    }

    return matchedToken;
  }

  /// Returns whether or not store contains a token that could be used for
  /// authenticating given [url].
  bool hasCredential(Uri url) {
    return credentials.any((it) => it.url == url);
  }

  /// Deletes tokens.json file from the disk.
  void deleteTokensFile() {
    deleteEntry(_tokensFile);
    log.message('tokens.json is deleted.');
  }

  /// Full path to the "tokens.json" file.
  String get _tokensFile => path.join(cacheRootDir, 'tokens.json');
}
