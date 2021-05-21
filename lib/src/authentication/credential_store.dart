// ignore_for_file: import_of_legacy_library_into_null_safe

import 'dart:convert';

import 'package:path/path.dart' as path;

import '../io.dart';
import '../system_cache.dart';
import 'credential.dart';

class CredentialStore {
  CredentialStore(this.cache);

  final SystemCache cache;

  /// Adds [credentials] for [server] into store.
  void addServer(String server, Credential credentials) {
    var key = server.toLowerCase();
    // Make sure server name ends with a backslash. It's here to deny possible
    // credential thief attach vectors where victim can add credential for
    // server 'https://safesite.com' and attacker could steal credentials by
    // requesting credentials for 'https://safesite.com.attacher.com', because
    // URL matcher (_serverMatches method) matches credential keys with the
    // beginning of the URL.
    if (!key.endsWith('/')) key += '/';
    serverCredentials[key] = credentials;
    _save();
  }

  /// Removes credentials for servers that [url] matches with.
  void removeServer(String url) {
    serverCredentials.removeWhere((key, value) => _serverKeyMatches(key, url));
    _save();
  }

  /// Returns credentials for server that [url] matches if any exists, otherwise
  /// returns null.
  Credential? getCredential(String url) {
    for (final key in serverCredentials.keys) {
      if (_serverKeyMatches(key, url)) {
        return serverCredentials[key];
      }
    }
  }

  /// Returns whether or not store has a credential for server that [url]
  /// matches to.
  bool hasCredential(String url) {
    for (final key in serverCredentials.keys) {
      if (_serverKeyMatches(key, url)) {
        return true;
      }
    }
    return false;
  }

  void _save() {
    _saveCredentials(serverCredentials);
  }

  Map<String, Credential>? _serverCredentials;
  Map<String, Credential> get serverCredentials =>
      _serverCredentials ??= _loadCredentials();

  String get _tokensFile => path.join(cache.rootDir, 'tokens.json');

  Map<String, Credential> _loadCredentials() {
    final path = _tokensFile;
    if (!fileExists(path)) return <String, Credential>{};

    final parsed = jsonDecode(readTextFile(path)) as Map<String, dynamic>;
    final result = parsed
        .map((key, value) => MapEntry(key, Credential.fromMap(value)))
          ..removeWhere((key, value) => value == null);

    return result.cast<String, Credential>();
  }

  void _saveCredentials(Map<String, Credential> credentials) {
    final path = _tokensFile;
    writeTextFile(
        path,
        jsonEncode(
            credentials.map((key, value) => MapEntry(key, value.toMap()))));
  }

  bool _serverKeyMatches(String serverKey, String url) {
    return serverKey.startsWith(url.toLowerCase());
  }
}
