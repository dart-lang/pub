// @dart=2.10

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
    serverCredentials[server] = credentials;
    _save();
  }

  /// Removes credentials for [server].
  void removeServer(String server) {
    serverCredentials.removeWhere((key, value) => key == server);
    _save();
  }

  /// Returns credentials for [server] if any exists, otherwise returns null.
  Credential getCredential(String server) {
    return serverCredentials[server];
  }

  void _save() {
    _saveCredentials(_serverCredentials);
  }

  Map<String, Credential> _serverCredentials;
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
}
