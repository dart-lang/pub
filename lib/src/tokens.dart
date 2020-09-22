// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;

import 'io.dart';
import 'log.dart' as log;
import 'system_cache.dart';
import 'utils.dart';

List<TokenEntry> _tokens;

/// Gets the token for the given uri
String getToken(SystemCache cache, Uri uri) {
  if (uri.host == 'pub.dartlang.org') return null;
  log.fine('Lookup token for ${uri.toString()}');
  var tokens = _loadTokens(cache);

  var found = tokens.firstWhere(
      (e) =>
          checkEndSlashUri(uri).toString().toLowerCase().startsWith(e.server),
      orElse: () => null);
  if (found == null) {
    log.fine('No token found for ${uri.toString()}');
    return null;
  }
  var tokenValue = found.token;

  if (tokenValue != null && tokenValue.startsWith('\$')) {
    var envVar = tokenValue.substring(1);
    tokenValue = Platform.environment[envVar];
    if (tokenValue == null) {
      log.warning('$envVar environment variable not set');
    }
  }
  return tokenValue;
}

/// Adds a token for a given server
void addToken(SystemCache cache, String server, String token) {
  var tokens = _loadTokens(cache);
  var normalizedServer = checkEndSlash(server).toLowerCase();

  var found = tokens.firstWhere((e) => e.server == normalizedServer,
      orElse: () => null);
  if (found != null) {
    tokens.remove(found);
    tokens.add(TokenEntry(server: normalizedServer, token: token));
    log.message('Token for $server updated');
  } else {
    tokens.add(TokenEntry(server: normalizedServer, token: token));
    log.message('Token for $server added');
  }
  _save(cache, tokens);
}

/// Removes the token for the given server
void removeToken(SystemCache cache, {String server, bool all = false}) {
  var tokens = _loadTokens(cache);
  if (all) {
    if (tokens.isEmpty) return;
    for (var item in tokens) {
      log.message('Log out ${item.server} successful.');
    }
    var tokensFile = _tokensFile(cache);
    if (entryExists(tokensFile)) deleteEntry(tokensFile);
    return;
  }
  var found = tokens.firstWhere(
      (e) => e.server == checkEndSlash(server).toLowerCase(),
      orElse: () => null);
  if (found == null) {
    log.message('No token found for $server.');
  } else {
    tokens.remove(found);
    log.message('Log out $server successful.');
  }
  _save(cache, tokens);
}

String validateServer(String server) {
  Uri uri;
  try {
    uri = Uri.parse(server);
  } on FormatException catch (e) {
    return '`server` must be a valid a URL: ${e.message}';
  }

  if (uri.scheme?.isEmpty ?? true) {
    return '`server` must include a scheme such as "https://".\n"$server" is invalid.';
  }
  if (uri.hasQuery) {
    return '`server` must not have a query string defined.\n"$server" is invalid.';
  }
  if (uri.host == 'pub.dartlang.org' || uri.host == 'pub.dev') {
    return '`server` cannot be the official package server.\n"$server" is invalid.';
  }
  return null;
}

void _save(SystemCache cache, List<TokenEntry> tokens) {
  var tokenPath = _tokensFile(cache);
  ensureDir(path.dirname(tokenPath));
  writeTextFile(tokenPath, jsonEncode(tokens));
  _tokens = tokens;
  log.fine('Saved secrets.json');
}

List<TokenEntry> _loadTokens(SystemCache cache) {
  log.fine('Loading tokens.');

  try {
    if (_tokens != null) return _tokens;
    _tokens = <TokenEntry>[];

    var path = _tokensFile(cache);
    if (!fileExists(path)) return _tokens;

    var response = readTextFile(path);
    if (response != null && response != '') {
      _tokens = List<TokenEntry>.from(
          json.decode(response).map((entry) => TokenEntry.fromJson(entry)));
    }

    return _tokens;
  } catch (e) {
    log.error('Warning: could not load the saved tokens: $e');
    return null;
  }
}

String _tokensFile(SystemCache cache) =>
    path.join(cache.rootDir, 'secrets.json');

class TokenEntry {
  final String server;
  final String token;
  TokenEntry({
    this.server,
    this.token,
  });
  factory TokenEntry.fromJson(Map<String, dynamic> json) => TokenEntry(
        server: json['server'],
        token: json['token'],
      );
  Map toJson() => {
        'server': server,
        'token': token,
      };
}
