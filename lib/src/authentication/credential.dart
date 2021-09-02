// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: import_of_legacy_library_into_null_safe

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
  Credential({required this.url, required this.token});

  /// Create [Credential] instance for bearer tokens.
  Credential.bearer(this.url, this.token);

  /// Deserialize [json] into [Credential] type.
  ///
  /// Throws [FormatException] if [json] is not a valid [Credential].
  factory Credential.fromJson(Map<String, dynamic> json) {
    if (json['url'] is! String) {
      throw FormatException('Url is not provided for the token');
    }

    final hostedUrl = validateAndNormalizeHostedUrl(json['url'] as String);

    if (json['token'] is! String) {
      throw FormatException('Secret token is not provided for the token');
    }

    return Credential(url: hostedUrl, token: json['token'] as String);
  }

  /// Server url which this token authenticates.
  final Uri url;

  /// Authentication token value
  final String token;

  /// Serializes [Credential] into json format.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{'url': url.toString(), 'token': token};
  }

  /// Returns future that resolves "Authorization" header value used for
  /// authenticating.
  // This method returns future to make sure in future we could use the
  // [Credential] interface for OAuth2.0 authentication too - which requires
  // token rotation (refresh) that's async job.
  Future<String> getAuthorizationHeaderValue() {
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
