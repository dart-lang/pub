// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: import_of_legacy_library_into_null_safe

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
  Credential({required this.url, required this.token, this.unknownFields});

  /// Create [Credential] instance for bearer tokens.
  Credential.bearer(this.url, this.token) : unknownFields = null;

  /// Deserialize [json] into [Credential] type.
  ///
  /// Throws [FormatException] if [json] is not a valid [Credential].
  factory Credential.fromJson(Map<String, dynamic> json) {
    if (json['url'] is! String) {
      throw FormatException('Url is not provided for the token');
    }

    final hostedUrl = validateAndNormalizeHostedUrl(json['url'] as String);
    final token = json['token'] is String ? json['token'] as String : null;

    const knownKeys = {'url', 'token'};
    final unknownFields = Map.fromEntries(
        json.entries.where((kv) => !knownKeys.contains(kv.key)));

    return Credential(
      url: hostedUrl,
      token: token,
      unknownFields: unknownFields,
    );
  }

  /// Server url which this token authenticates.
  final Uri url;

  /// Authentication token value
  final String? token;

  /// Unknown fields found in tokens.json. The fields might be created by the
  /// future version of pub tool. We don't want to override them when using the
  /// old SDK.
  final Map<String, dynamic>? unknownFields;

  /// Serializes [Credential] into json format.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'url': url.toString(),
      if (token != null) 'token': token,
      if (unknownFields != null) ...unknownFields!,
    };
  }

  /// Returns future that resolves "Authorization" header value used for
  /// authenticating.
  // This method returns future to make sure in future we could use the
  // [Credential] interface for OAuth2.0 authentication too - which requires
  // token rotation (refresh) that's async job.
  Future<String> getAuthorizationHeaderValue() {
    if (token == null) {
      throw DataException(
        'Saved credential for $url pub repository is not supported by current '
        'version of Dart SDK.',
      );
    }
    return Future.value('Bearer $token');
  }

  /// Returns whether or not given [url] could be authenticated using this
  /// credential.
  bool canAuthenticate(String url) {
    return _normalizeUrl(url).startsWith(_normalizeUrl(this.url.toString()));
  }

  static String _normalizeUrl(String url) {
    return (url.endsWith('/') ? url : '$url/').toLowerCase();
  }
}
