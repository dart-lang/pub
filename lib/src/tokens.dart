// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;

import 'io.dart';
import 'log.dart' as log;
import 'system_cache.dart';

Map<String, String> _tokens;

String getToken(Uri uri) {
  if (uri.host == 'pub.dartlang.org') return null;
  var tokens = _loadTokens();
  if (tokens != null && tokens.containsKey(uri.origin)) {
    var tokenValue = tokens[uri.origin];
    if (tokenValue != null && tokenValue.startsWith('\$')) {
      tokenValue = Platform.environment[tokenValue.substring(1)];
    }
  }
  return null;
}

Map<String, String> _loadTokens() {
  log.fine('Loading tokens.');

  try {
    if (_tokens != null) return _tokens;
    _tokens = <String, String>{};

    var path = _tokensFile();
    if (!fileExists(path)) return null;

    var response = readTextFile(path);
    if (response != null && response != '') {
      var items = List<TokenEntry>.from(
          json.decode(response).map((entry) => TokenEntry.fromJson(entry)));

      for (var item in items) {
        _tokens.putIfAbsent(item.host, () => item.token);
      }
    }

    return _tokens;
  } catch (e) {
    log.error('Warning: could not load the saved tokens: $e');
    return null;
  }
}

String _tokensFile() => path.join(SystemCache.defaultDir, 'tokens.json');

class TokenEntry {
  final String host;
  final String token;
  TokenEntry({
    this.host,
    this.token,
  });
  factory TokenEntry.fromJson(Map<String, dynamic> json) => TokenEntry(
        host: json['host'],
        token: json['token'],
      );
}
