// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import '../exceptions.dart';
import '../source/hosted.dart';
import '../utils.dart';

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
    required this.url,
    required this.unknownFields,
    required this.token,
    required this.env,
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
      json.entries.where((kv) => !knownKeys.contains(kv.key)),
    );

    /// Returns [String] value from [json] at [key] index or `null` if [json]
    /// doesn't contains [key].
    ///
    /// Throws [FormatException] if value type is not [String].
    String? string(String key) {
      if (json.containsKey(key)) {
        if (json[key] is! String) {
          throw FormatException('Provided $key value should be string');
        }
        return json[key] as String;
      }
      return null;
    }

    return Credential._internal(
      url: hostedUrl,
      unknownFields: unknownFields,
      token: string('token'),
      env: string('env'),
    );
  }

  /// Server url which this token authenticates.
  final Uri url;

  /// Authentication token value
  final String? token;

  /// Environment variable name that stores token value
  final String? env;

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
        'Saved credential for "$url" pub repository is not supported by '
        'current version of Dart SDK.',
      );
    }

    final String tokenValue;
    final environment = env;
    if (environment != null) {
      final value = Platform.environment[environment];
      if (value == null) {
        dataError(
          'Saved credential for "$url" pub repository requires environment '
          'variable named "$env" but not defined.',
        );
      }
      tokenValue = value;
    } else {
      tokenValue = token!;
    }
    if (!isValidBearerToken(tokenValue)) {
      dataError('Credential token for $url is not a valid Bearer token. '
          'It should match `^[a-zA-Z0-9._~+/=-]+\$`');
    }

    return Future.value('Bearer $tokenValue');
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
  // Either [token] or [env] should be defined to be valid.
  bool isValid() => (token == null) ^ (env == null);

  /// Whether [candidate] can be used as a bearer token.
  ///
  /// We limit tokens to be valid bearer tokens according to
  /// https://www.rfc-editor.org/rfc/rfc6750#section-2.1
  static bool isValidBearerToken(String candidate) {
    return RegExp(r'^[a-zA-Z0-9._~+/=-]+$').hasMatch(candidate);
  }

  static String _normalizeUrl(String url) {
    return (url.endsWith('/') ? url : '$url/').toLowerCase();
  }
}
