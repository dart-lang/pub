import 'dart:io';
import 'package:http/http.dart';

/// An HTTP [BaseClient] implementation that adds an `authorization`
/// header containing the given `Bearer` [token] to each request.
class BearerTokenClient extends BaseClient {
  /// The token to be sent with all requests.
  ///
  /// All requests will have the `authorization` header set to
  /// `'Bearer $token'`.
  final String token;

  /// The underlying [BaseClient] to use to send requests.
  final BaseClient httpClient;

  BearerTokenClient(this.token, this.httpClient);

  @override
  Future<StreamedResponse> send(BaseRequest request) {
    request.headers[HttpHeaders.authorizationHeader] = 'Bearer $token';
    return httpClient.send(request);
  }
}
