// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: import_of_legacy_library_into_null_safe

import 'dart:convert';

import 'package:path/path.dart' as path;

import '../io.dart';
import '../log.dart' as log;
import 'token.dart';

/// Stores and manages authentication credentials.
class TokenStore {
  TokenStore(this.cacheRootDir);

  /// Cache directory.
  final String cacheRootDir;

  List<Token>? _tokens;

  /// List of saved authentication tokens.
  ///
  /// Modifying this field will not write changes to the disk. You have to call
  /// [flush] to save changes.
  List<Token> get tokens => _tokens ??= _loadTokens();

  /// Reads "tokens.json" and parses / deserializes it into list of
  /// [Token].
  List<Token> _loadTokens() {
    final result = List<Token>.empty(growable: true);
    final path = _tokensFile;
    if (!fileExists(path)) {
      return result;
    }

    try {
      final json = jsonDecode(readTextFile(path));

      if (json is! Map<String, dynamic>) {
        throw FormatException('JSON contents is corrupted or not supported.');
      }
      if (json['version'] != 1) {
        throw FormatException('Version is not supported.');
      }

      if (json.containsKey('hosted')) {
        if (json['hosted'] is! List) {
          throw FormatException(
              'tokens.json format is invalid or not supported.');
        }

        result.addAll((json['hosted'] as List)
            .cast<Map<String, dynamic>>()
            .map((it) => Token.fromJson(it)));
      }
    } on FormatException catch (error, stackTrace) {
      log.error('Failed to load tokens.json', error, stackTrace);

      // When an invalid, damaged or not compatible version of token.json is
      // found, we remove it after showing error message. Otherwise the error
      // message will be displayed on each pub command.
      // Or instead we could write instructrions to execute
      //`pub token remove --all` if user couldn't solve the issue.
      deleteEntry(_tokensFile);
    }

    return result;
  }

  /// Writes [tokens] into "tokens.json".
  void _saveTokens(List<Token> tokens) {
    writeTextFile(
        _tokensFile,
        jsonEncode(<String, dynamic>{
          'version': 1,
          'hosted': tokens.map((it) => it.toJson()).toList(),
        }));
  }

  /// Writes latest state of the store to disk.
  void flush() {
    if (_tokens == null) {
      throw Exception('Schemes should be loaded before saving.');
    }
    _saveTokens(_tokens!);
  }

  /// Adds [token] into store and writes into disk.
  void addToken(Token token) {
    // Remove duplicate tokens
    tokens.removeWhere((it) => it.url == token.url);
    tokens.add(token);
    flush();
  }

  /// Removes tokens with matching [hostedUrl] from store. Returns whether or
  /// not there's a stored token with matching url.
  bool removeMatchingTokens(Uri hostedUrl) {
    var i = 0;
    var found = false;
    while (i < tokens.length) {
      if (tokens[i].url == hostedUrl) {
        tokens.removeAt(i);
        found = true;
      } else {
        i++;
      }
    }

    flush();

    return found;
  }

  /// Returns [Token] for authenticating given url or null if no matching token
  /// is found.
  Token? findToken(Uri url) {
    Token? matchedToken;
    for (final token in tokens) {
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
  bool hasToken(Uri url) {
    return tokens.any((it) => it.url == url);
  }

  /// Deletes tokens.json file from the disk.
  void deleteTokensFile() {
    deleteEntry(_tokensFile);
    log.message('tokens.json is deleted.');
  }

  /// Full path to the "tokens.json" file.
  String get _tokensFile => path.join(cacheRootDir, 'tokens.json');
}
