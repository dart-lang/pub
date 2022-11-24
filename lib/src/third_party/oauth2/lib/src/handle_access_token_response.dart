// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'authorization_exception.dart';
import 'credentials.dart';
import 'parameters.dart';

/// The amount of time to add as a "grace period" for credential expiration.
///
/// This allows credential expiration checks to remain valid for a reasonable
/// amount of time.
const _expirationGrace = Duration(seconds: 10);

/// Handles a response from the authorization server that contains an access
/// token.
///
/// This response format is common across several different components of the
/// OAuth2 flow.
///
/// By default, this follows the OAuth2 spec and requires the server's responses
/// to be in JSON format. However, some servers return non-standard response
/// formats, which can be parsed using the [getParameters] function.
///
/// This function is passed the `Content-Type` header of the response as well as
/// its body as a UTF-8-decoded string. It should return a map in the same
/// format as the [standard JSON response][].
///
/// [standard JSON response]: https://tools.ietf.org/html/rfc6749#section-5.1
Credentials handleAccessTokenResponse(http.Response response, Uri tokenEndpoint,
    DateTime startTime, List<String>? scopes, String delimiter,
    {Map<String, dynamic> Function(MediaType? contentType, String body)?
        getParameters}) {
  getParameters ??= parseJsonParameters;

  try {
    if (response.statusCode != 200) {
      _handleErrorResponse(response, tokenEndpoint, getParameters);
    }

    var contentTypeString = response.headers['content-type'];
    if (contentTypeString == null) {
      throw const FormatException('Missing Content-Type string.');
    }

    var parameters =
        getParameters(MediaType.parse(contentTypeString), response.body);

    for (var requiredParameter in ['access_token', 'token_type']) {
      if (!parameters.containsKey(requiredParameter)) {
        throw FormatException(
            'did not contain required parameter "$requiredParameter"');
      } else if (parameters[requiredParameter] is! String) {
        throw FormatException(
            'required parameter "$requiredParameter" was not a string, was '
            '"${parameters[requiredParameter]}"');
      }
    }

    // TODO(nweiz): support the "mac" token type
    // (http://tools.ietf.org/html/draft-ietf-oauth-v2-http-mac-01)
    if ((parameters['token_type'] as String).toLowerCase() != 'bearer') {
      throw FormatException(
          '"$tokenEndpoint": unknown token type "${parameters['token_type']}"');
    }

    var expiresIn = parameters['expires_in'];
    if (expiresIn != null) {
      if (expiresIn is String) {
        try {
          expiresIn = double.parse(expiresIn).toInt();
        } on FormatException {
          throw FormatException(
              'parameter "expires_in" could not be parsed as in, was: "$expiresIn"');
        }
      } else if (expiresIn is! int) {
        throw FormatException(
            'parameter "expires_in" was not an int, was: "$expiresIn"');
      }
    }

    for (var name in ['refresh_token', 'id_token', 'scope']) {
      var value = parameters[name];
      if (value != null && value is! String) {
        throw FormatException(
            'parameter "$name" was not a string, was "$value"');
      }
    }

    var scope = parameters['scope'] as String?;
    if (scope != null) scopes = scope.split(delimiter);

    var expiration = expiresIn == null
        ? null
        : startTime.add(Duration(seconds: expiresIn as int) - _expirationGrace);

    return Credentials(
      parameters['access_token'] as String,
      refreshToken: parameters['refresh_token'] as String?,
      idToken: parameters['id_token'] as String?,
      tokenEndpoint: tokenEndpoint,
      scopes: scopes,
      expiration: expiration,
    );
  } on FormatException catch (e) {
    throw FormatException('Invalid OAuth response for "$tokenEndpoint": '
        '${e.message}.\n\n${response.body}');
  }
}

/// Throws the appropriate exception for an error response from the
/// authorization server.
void _handleErrorResponse(
    http.Response response, Uri tokenEndpoint, GetParameters getParameters) {
  // OAuth2 mandates a 400 or 401 response code for access token error
  // responses. If it's not a 400 reponse, the server is either broken or
  // off-spec.
  if (response.statusCode != 400 && response.statusCode != 401) {
    var reason = '';
    var reasonPhrase = response.reasonPhrase;
    if (reasonPhrase != null && reasonPhrase.isNotEmpty) {
      reason = ' $reasonPhrase';
    }
    throw FormatException('OAuth request for "$tokenEndpoint" failed '
        'with status ${response.statusCode}$reason.\n\n${response.body}');
  }

  var contentTypeString = response.headers['content-type'];
  var contentType =
      contentTypeString == null ? null : MediaType.parse(contentTypeString);

  var parameters = getParameters(contentType, response.body);

  if (!parameters.containsKey('error')) {
    throw const FormatException('did not contain required parameter "error"');
  } else if (parameters['error'] is! String) {
    throw FormatException('required parameter "error" was not a string, was '
        '"${parameters["error"]}"');
  }

  for (var name in ['error_description', 'error_uri']) {
    var value = parameters[name];

    if (value != null && value is! String) {
      throw FormatException('parameter "$name" was not a string, was "$value"');
    }
  }

  var uriString = parameters['error_uri'] as String?;
  var uri = uriString == null ? null : Uri.parse(uriString);
  var description = parameters['error_description'] as String?;
  throw AuthorizationException(parameters['error'] as String, description, uri);
}
