// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'authorization_exception.dart';
import 'credentials.dart';
import 'expiration_exception.dart';

/// An OAuth2 client.
///
/// This acts as a drop-in replacement for an [http.Client], while sending
/// OAuth2 authorization credentials along with each request.
///
/// The client also automatically refreshes its credentials if possible. When it
/// makes a request, if its credentials are expired, it will first refresh them.
/// This means that any request may throw an [AuthorizationException] if the
/// refresh is not authorized for some reason, a [FormatException] if the
/// authorization server provides ill-formatted responses, or an
/// [ExpirationException] if the credentials are expired and can't be refreshed.
///
/// The client will also throw an [AuthorizationException] if the resource
/// server returns a 401 response with a WWW-Authenticate header indicating that
/// the current credentials are invalid.
///
/// If you already have a set of [Credentials], you can construct a [Client]
/// directly. However, in order to first obtain the credentials, you must
/// authorize. At the time of writing, the only authorization method this
/// library supports is [AuthorizationCodeGrant].
class Client extends http.BaseClient {
  /// The client identifier for this client.
  ///
  /// The authorization server will issue each client a separate client
  /// identifier and secret, which allows the server to tell which client is
  /// accessing it. Some servers may also have an anonymous identifier/secret
  /// pair that any client may use.
  ///
  /// This is usually global to the program using this library.
  final String? identifier;

  /// The client secret for this client.
  ///
  /// The authorization server will issue each client a separate client
  /// identifier and secret, which allows the server to tell which client is
  /// accessing it. Some servers may also have an anonymous identifier/secret
  /// pair that any client may use.
  ///
  /// This is usually global to the program using this library.
  ///
  /// Note that clients whose source code or binary executable is readily
  /// available may not be able to make sure the client secret is kept a secret.
  /// This is fine; OAuth2 servers generally won't rely on knowing with
  /// certainty that a client is who it claims to be.
  final String? secret;

  /// The credentials this client uses to prove to the resource server that it's
  /// authorized.
  ///
  /// This may change from request to request as the credentials expire and the
  /// client refreshes them automatically.
  Credentials get credentials => _credentials;
  Credentials _credentials;

  /// Callback to be invoked whenever the credentials refreshed.
  final CredentialsRefreshedCallback? _onCredentialsRefreshed;

  /// Whether to use HTTP Basic authentication for authorizing the client.
  final bool _basicAuth;

  /// The underlying HTTP client.
  http.Client? _httpClient;

  /// Creates a new client from a pre-existing set of credentials.
  ///
  /// When authorizing a client for the first time, you should use
  /// [AuthorizationCodeGrant] or [resourceOwnerPasswordGrant] instead of
  /// constructing a [Client] directly.
  ///
  /// [httpClient] is the underlying client that this forwards requests to after
  /// adding authorization credentials to them.
  ///
  /// Throws an [ArgumentError] if [secret] is passed without [identifier].
  Client(this._credentials,
      {this.identifier,
      this.secret,
      CredentialsRefreshedCallback? onCredentialsRefreshed,
      bool basicAuth = true,
      http.Client? httpClient})
      : _basicAuth = basicAuth,
        _onCredentialsRefreshed = onCredentialsRefreshed,
        _httpClient = httpClient ?? http.Client() {
    if (identifier == null && secret != null) {
      throw ArgumentError('secret may not be passed without identifier.');
    }
  }

  /// Sends an HTTP request with OAuth2 authorization credentials attached.
  ///
  /// This will also automatically refresh this client's [Credentials] before
  /// sending the request if necessary.
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (credentials.isExpired) {
      if (!credentials.canRefresh) throw ExpirationException(credentials);
      await refreshCredentials();
    }

    request.headers['authorization'] = 'Bearer ${credentials.accessToken}';
    var response = await _httpClient!.send(request);

    if (response.statusCode != 401) return response;
    if (!response.headers.containsKey('www-authenticate')) return response;

    List<AuthenticationChallenge> challenges;
    try {
      challenges = AuthenticationChallenge.parseHeader(
          response.headers['www-authenticate']!);
    } on FormatException {
      return response;
    }

    var challenge = challenges
        .firstWhereOrNull((challenge) => challenge.scheme == 'bearer');
    if (challenge == null) return response;

    var params = challenge.parameters;
    if (!params.containsKey('error')) return response;

    throw AuthorizationException(params['error']!, params['error_description'],
        params['error_uri'] == null ? null : Uri.parse(params['error_uri']!));
  }

  /// A [Future] used to track whether [refreshCredentials] is running.
  Future<Credentials>? _refreshingFuture;

  /// Explicitly refreshes this client's credentials. Returns this client.
  ///
  /// This will throw a [StateError] if the [Credentials] can't be refreshed, an
  /// [AuthorizationException] if refreshing the credentials fails, or a
  /// [FormatException] if the authorization server returns invalid responses.
  ///
  /// You may request different scopes than the default by passing in
  /// [newScopes]. These must be a subset of the scopes in the
  /// [Credentials.scopes] field of [Client.credentials].
  Future<Client> refreshCredentials([List<String>? newScopes]) async {
    if (!credentials.canRefresh) {
      var prefix = 'OAuth credentials';
      if (credentials.isExpired) prefix = '$prefix have expired and';
      throw StateError("$prefix can't be refreshed.");
    }

    // To make sure that only one refresh happens when credentials are expired
    // we track it using the [_refreshingFuture]. And also make sure that the
    // _onCredentialsRefreshed callback is only called once.
    if (_refreshingFuture == null) {
      try {
        _refreshingFuture = credentials.refresh(
          identifier: identifier,
          secret: secret,
          newScopes: newScopes,
          basicAuth: _basicAuth,
          httpClient: _httpClient,
        );
        _credentials = await _refreshingFuture!;
        _onCredentialsRefreshed?.call(_credentials);
      } finally {
        _refreshingFuture = null;
      }
    } else {
      await _refreshingFuture;
    }

    return this;
  }

  /// Closes this client and its underlying HTTP client.
  @override
  void close() {
    _httpClient?.close();
    _httpClient = null;
  }
}
