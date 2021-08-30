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
///   "credential": {
///     "kind": "Bearer",
///     "token": "gjrjo7Tm2F0u64cTsECDq4jBNZYhco"
///   }
/// }
/// ```
class Token {
  Token({required this.url, required this.kind, required this.token});

  /// Create [Token] instance with the `'Bearer'` kind.
  Token.bearer(this.url, this.token) : kind = 'Bearer';

  /// Deserialize [json] into [Token] type.
  factory Token.fromJson(Map<String, dynamic> json) {
    if (json['url'] is! String) {
      throw FormatException('Url is not provided for the token');
    }

    var hostedUrl = validateAndNormalizeHostedUrl(json['url'] as String);

    if (json['credential'] is! Map<String, dynamic>) {
      throw FormatException('Credential is not provided for the token');
    }

    final kindValue = json['credential']['kind'];

    if (kindValue is! String) {
      throw FormatException('Credential kind is not provided for the token');
    }

    if (!const ['Bearer'].contains(kindValue)) {
      throw FormatException('$kindValue is unsupported credential kind value');
    }

    if (json['credential']['token'] is! String) {
      throw FormatException('Credential token is not provided for the token');
    }

    return Token(
      url: hostedUrl,
      kind: kindValue,
      token: json['credential']['token'] as String,
    );
  }

  /// Server url which this token authenticates.
  final Uri url;

  /// Specifies authentication token kind.
  ///
  /// The supported values are: `Bearer`
  final String kind;

  /// Authentication token value
  final String token;

  /// Serializes [Token] into json format.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'url': url.toString(),
      'credential': <String, dynamic>{'kind': kind, 'token': token},
    };
  }

  /// Returns future that resolves "Authorization" header value used for
  /// authenticating.
  ///
  /// This method returns future to make sure in future we could use the [Token]
  /// interface for OAuth2.0 authentication too - which requires token rotation
  /// (refresh) that's async job.
  Future<String> getAuthorizationHeaderValue() {
    return Future.value('$kind $token');
  }

  /// Returns whether or not given [url] could be authenticated using this
  /// token.
  bool canAuthenticate(String url) {
    return _normalizeUrl(url).startsWith(_normalizeUrl(this.url.toString()));
  }

  static String _normalizeUrl(String url) {
    return (url.endsWith('/') ? url : '$url/').toLowerCase();
  }
}
