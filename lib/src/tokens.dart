// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;

import 'io.dart';
import 'log.dart' as log;
import 'system_cache.dart';

List<TokenEntry> _tokens;

/// Gets the token for the given uri
String getToken(Uri uri) {
  if (uri.host == 'pub.dartlang.org') return null;
  var tokens = _loadTokens();

  var found = tokens.firstWhere((e) => e.server == uri.origin.toLowerCase(),
      orElse: () => null);
  if (found == null) {
    return null;
  }
  var tokenValue = found.token;

  if (tokenValue != null && tokenValue.startsWith('\$')) {
    tokenValue = Platform.environment[tokenValue.substring(1)];
    if (tokenValue == null) {
      log.warning('$tokenValue not set');
    }
  }
  return tokenValue;
}

/// Adds a token for a given server
void addToken(String server, String token) {
  var tokens = _loadTokens();

  var found = tokens.firstWhere((e) => e.server == server.toLowerCase(),
      orElse: () => null);
  if (found != null) {
    found.token = token;
    log.message('Token for $server updated');
  } else {
    found = TokenEntry(server: server.toLowerCase(), token: token);
    tokens.add(found);
    log.message('Token for $server added');
  }
  _save(tokens);
}

/// Removes the token for the given server
void removeToken({String server, bool all = false}) {
  if (all) {
    var tokensFile = _tokensFile();
    log.message('Deleting $tokensFile');
    if (entryExists(tokensFile)) deleteEntry(tokensFile);
    return;
  }

  var tokens = _loadTokens();
  var found = tokens.firstWhere((e) => e.server == server.toLowerCase(),
      orElse: () => null);
  if (found == null) {
    log.warning('$server not found in tokens.json');
  } else {
    tokens.remove(found);
    log.message('Token for $server removed');
  }
  _save(tokens);
}

/// Shows the user a formatted list of tokens.
void listTokens() {
  var tokens = _loadTokens();
  if (tokens.isEmpty) return;

  var largest = tokens.reduce(
      (curr, next) => curr.server.length > next.server.length ? curr : next);

  tokens
    ..sort((entry1, entry2) => entry1.server.compareTo(entry2.server))
    ..forEach(
        (entry) => log.message(_formatToken(entry, largest.server.length)));
}

String validateServer(String server) {
  var uri = Uri.parse(server);
  if (uri.scheme?.isEmpty ?? true) {
    return '`server` must include a scheme such as "https://". '
        '$server is invalid';
  }
  if (!uri.hasEmptyPath) {
    return '`server` must not have a path defined. '
        '$server is invalid';
  }
  if (uri.hasQuery) {
    return '`server` must not have a query string defined. '
        '$server is invalid';
  }
  return null;
}

/// Returns formatted string representing the token.
String _formatToken(TokenEntry item, int maxServerLength) {
  return '${log.bold(item.server.padRight(maxServerLength))} -> ${item.token}';
}

void _save(List<TokenEntry> tokens) {
  var path = _tokensFile();
  writeTextFile(path, jsonEncode(tokens), dontLogContents: true);
}

List<TokenEntry> _loadTokens() {
  log.fine('Loading tokens.');

  try {
    if (_tokens != null) return _tokens;
    _tokens = <TokenEntry>[];

    var path = _tokensFile();
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

String _tokensFile() => path.join(SystemCache.defaultDir, 'tokens.json');

class TokenEntry {
  String server;
  String token;
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
