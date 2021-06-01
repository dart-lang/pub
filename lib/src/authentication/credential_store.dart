// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: import_of_legacy_library_into_null_safe

import 'dart:convert';

import 'package:path/path.dart' as path;

import '../io.dart';
import '../log.dart' as log;
import 'credential.dart';
import 'scheme.dart';

/// Stores and manages authentication credentials.
class CredentialStore {
  CredentialStore(this.cacheRootDir);

  /// Cache directory.
  final String cacheRootDir;

  List<AuthenticationScheme>? _schemes;

  /// List of saved authentication schemes.
  ///
  /// Modifying this field will not write changes to the disk. You have to call
  /// [flush] to save changes.
  List<AuthenticationScheme> get schemes => _schemes ??= _loadSchemes();

  /// Reads "tokens.json" and parses / deserializes it into list of
  /// [AuthenticationScheme].
  List<AuthenticationScheme> _loadSchemes() {
    final result = List<AuthenticationScheme>.empty(growable: true);
    final path = _tokensFile;
    if (!fileExists(path)) {
      return result;
    }

    try {
      final json = jsonDecode(readTextFile(path));

      if (json is! Map<String, dynamic>) {
        throw FormatException('JSON contents is corrupted or not supported.');
      }
      if (json['version'] != '1.0') {
        throw FormatException('Version is not supported.');
      }

      if (json.containsKey('hosted')) {
        if (json['hosted'] is! List) {
          throw FormatException(
              'tokens.json format is invalid or not supported.');
        }

        result.addAll((json['hosted'] as List)
            .cast<Map<String, dynamic>>()
            .map(HostedAuthenticationScheme.fromJson));
      }
    } on FormatException catch (error, stackTrace) {
      log.error('Failed to load tokens.json.', error, stackTrace);
    }

    return result;
  }

  /// Saves [schemes] into "tokens.json".
  void _saveSchemes(List<AuthenticationScheme> schemes) {
    writeTextFile(
        _tokensFile,
        jsonEncode(<String, dynamic>{
          'version': '1.0',
          'hosted': schemes
              .whereType<HostedAuthenticationScheme>()
              .map((it) => it.toJson())
              .toList(),
        }));
  }

  /// Writes latest state of the store to disk.
  void flush() {
    if (_schemes == null) {
      throw Exception('Schemes should be loaded before saving.');
    }
    _saveSchemes(_schemes!);
  }

  /// Adds [scheme] into store.
  void addScheme(AuthenticationScheme scheme) {
    schemes.add(scheme);
    flush();
  }

  /// Creates [HostedAuthenticationScheme] for [baseUrl] with [credential], then
  /// adds it to store.
  void addHostedScheme(String baseUrl, Credential credential) {
    schemes.add(HostedAuthenticationScheme(
      baseUrl: baseUrl,
      credential: credential,
    ));
    flush();
  }

  /// Removes [HostedAuthenticationScheme] matching to [url] from store.
  void removeMatchingHostedSchemes(String url) {
    final schemesToRemove =
        schemes.where((it) => it.canAuthenticate(url)).toList();
    if (schemesToRemove.isNotEmpty) {
      for (final scheme in schemesToRemove) {
        schemes.remove(scheme);
        log.message('Logging out of ${scheme.baseUrl}.');
      }

      flush();
    } else {
      log.message('No matching credential found for $url. Cannot log out.');
    }
  }

  /// Returns matching authentication scheme to given [url] or returns `null` if
  /// no matches found.
  AuthenticationScheme? findScheme(String url) {
    AuthenticationScheme? matchedScheme;
    for (final scheme in schemes) {
      if (scheme.canAuthenticate(url)) {
        if (matchedScheme == null) {
          matchedScheme = scheme;
        } else {
          log.warning(
            'Found multiple matching authentication schemes for url "$url". '
            'First matching scheme will be used for authentication.',
          );
        }
      }
    }
  }

  /// Returns whether or not store contains a scheme that could be used for
  /// authenticating give [url].
  bool hasScheme(String url) {
    return schemes.any((it) => it.canAuthenticate(url));
  }

  /// Full path to the "tokens.json" file.
  String get _tokensFile => path.join(cacheRootDir, 'tokens.json');
}
