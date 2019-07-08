import 'dart:async';
import 'dart:io';
import 'package:http/http.dart';
import 'package:pub/src/exceptions.dart';
import 'package:pub/src/http.dart';

/// An HTTP [BaseClient] implementation that adds an `authorization`
/// header containing the given `Bearer` [getToken] to each request.
class BearerTokenClient extends BaseClient {
  /// The underlying [BaseClient] to use to send requests.
  final BaseClient httpClient;

  /// A callback that takes a server response (potentially `null`),
  /// and returns a token to be sent with all requests.
  /// If the server returns a 401, this function will be invoked
  /// and used to prompt the user for a new token.
  ///
  /// All requests will have the `authorization` header set to
  /// `'Bearer $token'`.
  final FutureOr<String> Function(String) getToken;

  String _token;

  BearerTokenClient(this.httpClient, this._token, this.getToken);

  @override
  void close() {
    httpClient.close();
    super.close();
  }

  @override
  Future<StreamedResponse> send(BaseRequest request) {
    if (_token != null) {
      request.headers[HttpHeaders.authorizationHeader] = 'Bearer $_token';
    }

    return httpClient.send(request).then((response) async {
      if (response.statusCode != HttpStatus.unauthorized) {
        return response;
      } else {
        // If we get a 401, print the reply from the server, so
        // that servers can give custom instructions to users on
        // how to sign in.
        String serverResponse;

        try {
          handleJsonError(await Response.fromStream(response));
        } on ApplicationException catch (e) {
          serverResponse = e.message;
        }

        _token = null; // Remove the current token.
        _token = await getToken(serverResponse); // Prompt again.
        request.headers[HttpHeaders.authorizationHeader] = 'Bearer $_token';
        return httpClient.send(request);
      }
    });
  }
}
