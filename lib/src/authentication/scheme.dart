import 'credential.dart';

// TODO(themisir): Add authentication scopes. It'll be used to check whether or
// not the request should be authenticated. For example official pub.dev server
// scheme could define scopes as [AuthenticationScope.publish] which means it
// only requires authentication for publish command.

/// Abstract interface for authentication scheme. It's used for validating
/// request URLs and contains [credential] which will be used for
/// authentication.
abstract class AuthenticationScheme {
  /// Authentication credential which used to resolve `Authorization` header
  /// value.
  Credential get credential;

  /// Server base URL which this authentication scheme could authenticate.
  String get baseUrl;

  /// Returns whether or not given [url] could be authenticated using
  /// [credential].
  bool canAuthenticate(String url);

  /// Serializes this authentication scheme into json format.
  Map<String, Object> toJson();

  // TODO(themisir): This method will be used for prompting for user input
  // to get credentials in future.
  //
  // For example OAuth2AuthenticationScheme could implement this method to
  // launch http server and open authentication URL in browser.
  // Future<String?> prompt();
}

/// Authentication scheme that used by
class HostedAuthenticationScheme implements AuthenticationScheme {
  HostedAuthenticationScheme({
    required this.baseUrl,
    required this.credential,
  });

  /// Deserializes [HostedAuthenticationScheme] from given json [map].
  static HostedAuthenticationScheme fromJson(Map<String, dynamic> map) {
    if (map['url'] is! String) {
      throw FormatException(
          'Server base URL for authentication scheme is not provided.');
    }
    if (map['credential'] is! Map<String, dynamic>) {
      throw FormatException(
          'Authentication scheme does not contains a valid credential.');
    }
    return HostedAuthenticationScheme(
      baseUrl: map['url'] as String,
      credential:
          Credential.fromJson(map['credential'] as Map<String, dynamic>),
    );
  }

  static String _normalizeUrl(String url) {
    return (url.endsWith('/') ? url : '$url/').toLowerCase();
  }

  @override
  final Credential credential;

  /// Hosted pub server base url.
  @override
  final String baseUrl;

  @override
  Map<String, Object> toJson() =>
      <String, Object>{'url': baseUrl, 'credential': credential.toJson()};

  @override
  bool canAuthenticate(String url) {
    return _normalizeUrl(url).startsWith(_normalizeUrl(baseUrl));
  }
}
