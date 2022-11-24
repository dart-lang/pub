// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'client.dart';
import 'credentials.dart';
import 'handle_access_token_response.dart';
import 'utils.dart';

/// Obtains credentials using a [resource owner password grant](https://tools.ietf.org/html/rfc6749#section-1.3.3).
///
/// This mode of authorization uses the user's username and password to obtain
/// an authentication token, which can then be stored. This is safer than
/// storing the username and password directly, but it should be avoided if any
/// other authorization method is available, since it requires the user to
/// provide their username and password to a third party (you).
///
/// The client [identifier] and [secret] may be issued by the server, and are
/// used to identify and authenticate your specific OAuth2 client. These are
/// usually global to the program using this library.
///
/// The specific permissions being requested from the authorization server may
/// be specified via [scopes]. The scope strings are specific to the
/// authorization server and may be found in its documentation. Note that you
/// may not be granted access to every scope you request; you may check the
/// [Credentials.scopes] field of [Client.credentials] to see which scopes you
/// were granted.
///
/// The scope strings will be separated by the provided [delimiter]. This
/// defaults to `" "`, the OAuth2 standard, but some APIs (such as Facebook's)
/// use non-standard delimiters.
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
Future<Client> resourceOwnerPasswordGrant(
    Uri authorizationEndpoint, String username, String password,
    {String? identifier,
    String? secret,
    Iterable<String>? scopes,
    bool basicAuth = true,
    CredentialsRefreshedCallback? onCredentialsRefreshed,
    http.Client? httpClient,
    String? delimiter,
    Map<String, dynamic> Function(MediaType? contentType, String body)?
        getParameters}) async {
  delimiter ??= ' ';
  var startTime = DateTime.now();

  var body = {
    'grant_type': 'password',
    'username': username,
    'password': password
  };

  var headers = <String, String>{};

  if (identifier != null) {
    if (basicAuth) {
      headers['Authorization'] = basicAuthHeader(identifier, secret!);
    } else {
      body['client_id'] = identifier;
      if (secret != null) body['client_secret'] = secret;
    }
  }

  if (scopes != null && scopes.isNotEmpty) {
    body['scope'] = scopes.join(delimiter);
  }

  httpClient ??= http.Client();
  var response = await httpClient.post(authorizationEndpoint,
      headers: headers, body: body);

  var credentials = handleAccessTokenResponse(
      response, authorizationEndpoint, startTime, scopes?.toList(), delimiter,
      getParameters: getParameters);
  return Client(credentials,
      identifier: identifier,
      secret: secret,
      httpClient: httpClient,
      onCredentialsRefreshed: onCredentialsRefreshed);
}
