// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart=2.11

import 'dart:io';

import 'package:meta/meta.dart';

import '../exceptions.dart';
import '../source/hosted.dart';

/// Token is a structure for storing authentication credentials for third-party
/// pub registries. A token holds registry [url], credential [kind] and [token]
/// itself.
///
/// Token could be serialized into and from JSON format structured like
/// this:
///
/// ```json
/// {
///   "url": "https://example.com/",
///   "token": "gjrjo7Tm2F0u64cTsECDq4jBNZYhco"
/// }
/// ```
class Credential {
  /// Internal constructor that's only used by [fromJson].
  Credential._internal({
    @required this.url,
    @required this.unknownFields,
    @required this.token,
    @required this.env,
  });

  /// Create credential that stores clear text token.
  Credential.token(this.url, this.token)
      : env = null,
        unknownFields = const <String, dynamic>{};

  /// Create credential that stores environment variable name that stores token
  /// value.
  Credential.env(this.url, this.env)
      : token = null,
        unknownFields = const <String, dynamic>{};

  /// Deserialize [json] into [Credential] type.
  ///
  /// Throws [FormatException] if [json] is not a valid [Credential].
  factory Credential.fromJson(Map<String, dynamic> json) {
    if (json['url'] is! String) {
      throw FormatException('Url is not provided for the credential');
    }

    final hostedUrl = validateAndNormalizeHostedUrl(json['url'] as String);

    const knownKeys = {'url', 'token', 'env'};
    final unknownFields = Map.fromEntries(
        json.entries.where((kv) => !knownKeys.contains(kv.key)));

    String _optional(String key) {
      return json[key] is String ? json[key] as String : null;
    }

    return Credential._internal(
      url: hostedUrl,
      unknownFields: unknownFields,
      token: _optional('token'),
      env: _optional('env'),
    );
  }

  /// Server url which this token authenticates.
  final Uri url;

  /// Authentication token value
  final String token;

  /// Environment variable name that stores token value
  final String env;

  /// Unknown fields found in pub-tokens.json. The fields might be created by the
  /// future version of pub tool. We don't want to override them when using the
  /// old SDK.
  final Map<String, dynamic> unknownFields;

  /// Serializes [Credential] into json format.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'url': url.toString(),
      if (token != null) 'token': token,
      if (env != null) 'env': env,
      ...unknownFields,
    };
  }

  /// Returns future that resolves "Authorization" header value used for
  /// authenticating.
  ///
  /// Throws [DataException] if credential is not valid.
  // This method returns future to make sure in future we could use the
  // [Credential] interface for OAuth2.0 authentication too - which requires
  // token rotation (refresh) that's async job.
  Future<String> getAuthorizationHeaderValue() {
    if (!isValid()) {
      throw DataException(
        'Saved credential for $url pub repository is not supported by current '
        'version of Dart SDK.',
      );
    }

    if (env != null) {
      final value = Platform.environment[env];
      if (value == null) {
        throw DataException(
          'Saved credential for $url pub repository requires environment '
          'variable named $env but not defined.',
        );
      }
      return Future.value('Bearer $value');
    }

    return Future.value('Bearer $token');
  }

  /// Returns whether or not given [url] could be authenticated using this
  /// credential.
  bool canAuthenticate(String url) {
    return _normalizeUrl(url).startsWith(_normalizeUrl(this.url.toString()));
  }

  /// Returns boolean indicates whether or not the credentials is valid.
  ///
  /// This method might return `false` when a `pub-tokens.json` file created by
  /// future SDK used by pub tool from old SDK.
  bool isValid() => token != null || env != null;

  static String _normalizeUrl(String url) {
    return (url.endsWith('/') ? url : '$url/').toLowerCase();
  }
}
