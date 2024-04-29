// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/retry.dart';
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'http.dart';
import 'io.dart';
import 'log.dart' as log;
import 'utils.dart';

/// The global HTTP client with basic retries. Used instead of retryForHttp for
/// OAuth calls because the OAuth2 package requires a client to be passed. While
/// the retry logic is more basic, this is fine for the publishing process.
final _retryHttpClient = RetryClient(
  globalHttpClient,
  when: (response) => response.statusCode >= 500,
  whenError: (e, _) => isHttpIOException(e),
);

/// The pub client's OAuth2 identifier.
const _identifier =
    '818368855108-8grd2eg9tj9f38os6f1urbcvsq399u8n.apps.googleusercontent.com';

/// The pub client's OAuth2 secret.
///
/// This isn't actually meant to be kept a secret.
const _secret = 'SWeqj8seoJW0w7_CpEPFLX0K';

/// The URL from which the pub client will retrieve Google's OIDC endpoint URIs.
///
/// [Google OpenID Connect documentation]: https://developers.google.com/identity/openid-connect/openid-connect#discovery
final _oidcDiscoveryDocumentEndpoint =
    Uri.https('accounts.google.com', '/.well-known/openid-configuration');

/// The URL to which the user will be directed to authorize the pub client to
/// get an OAuth2 access token.
///
/// `access_type=offline` and `approval_prompt=force` ensures that we always get
/// a refresh token from the server. See the [Google OAuth2 documentation][].
///
/// [Google OAuth2 documentation]: https://developers.google.com/accounts/docs/OAuth2WebServer#offline
final _authorizationEndpoint =
    Uri.parse('https://accounts.google.com/o/oauth2/auth?access_type=offline'
        '&approval_prompt=force');

/// The URL from which the pub client will request an access token once it's
/// been authorized by the user.
///
/// This can be controlled externally by setting the `_PUB_TEST_TOKEN_ENDPOINT`
/// environment variable.
Uri get tokenEndpoint {
  final tokenEndpoint = Platform.environment['_PUB_TEST_TOKEN_ENDPOINT'];
  if (tokenEndpoint != null) {
    return Uri.parse(tokenEndpoint);
  } else {
    return _tokenEndpoint;
  }
}

final _tokenEndpoint = Uri.parse('https://accounts.google.com/o/oauth2/token');

/// The OAuth2 scopes that the pub client needs.
///
/// Currently the client only needs the user's email so that the server can
/// verify their identity.
final _scopes = ['openid', 'https://www.googleapis.com/auth/userinfo.email'];

/// An in-memory cache of the user's OAuth2 credentials.
///
/// This should always be the same as the credentials file stored in the system
/// cache.
Credentials? _credentials;

/// Delete the cached credentials, if they exist.
void _clearCredentials() {
  _credentials = null;
  final credentialsFile = _credentialsFile();
  if (credentialsFile != null && entryExists(credentialsFile)) {
    deleteEntry(credentialsFile);
  }
}

/// Try to delete the cached credentials.
void logout() {
  final credentialsFile = _credentialsFile();
  if (credentialsFile != null && entryExists(credentialsFile)) {
    log.message('Logging out of pub.dev.');
    log.message('Deleting $credentialsFile');
    _clearCredentials();
  } else {
    log.message(
      'No existing credentials file $credentialsFile. Cannot log out.',
    );
  }
}

/// Asynchronously passes an OAuth2 [_Client] to [fn].
///
/// Does not close the client, since that would close the shared client. It must
/// be closed elsewhere.
///
/// This takes care of loading and saving the client's credentials, as well as
/// prompting the user for their authorization. It will also re-authorize and
/// re-run [fn] if a recoverable authorization error is detected.
Future<T> withClient<T>(Future<T> Function(http.Client) fn) {
  return _getClient().then((client) {
    return fn(client).whenComplete(() {
      // TODO(sigurdm): refactor the http subsystem, so we can close [client]
      // here.

      // Be sure to save the credentials even when an error happens.
      _saveCredentials(client.credentials);
    });
  }).catchError((Object error) {
    if (error is _ExpirationException) {
      log.error("Pub's authorization to upload packages has expired and "
          "can't be automatically refreshed.");
      return withClient(fn);
    } else if (error is _AuthorizationException) {
      var message = 'OAuth2 authorization failed';
      if (error.description != null) {
        message = '$message (${error.description})';
      }
      log.error('$message.');
      _clearCredentials();
      return withClient(fn);
    } else {
      // ignore: only_throw_errors
      throw error;
    }
  });
}

/// Gets a new OAuth2 client.
///
/// If saved credentials are available, those are used; otherwise, the user is
/// prompted to authorize the pub client.
Future<_Client> _getClient() async {
  final credentials = loadCredentials();
  if (credentials == null) return await _authorize();

  final client = _Client(
    credentials,
    identifier: _identifier,
    secret: _secret,
    // Google's OAuth2 API doesn't support basic auth.
    basicAuth: false,
    httpClient: _retryHttpClient,
  );
  _saveCredentials(client.credentials);
  return client;
}

/// Loads the user's OAuth2 credentials from the in-memory cache or the
/// filesystem if possible.
///
/// If the credentials can't be loaded for any reason, the returned [Future]
/// completes to `null`.
Credentials? loadCredentials() {
  log.fine('Loading OAuth2 credentials.');

  try {
    if (_credentials != null) return _credentials;

    final path = _credentialsFile();
    if (path == null || !fileExists(path)) return null;

    final credentials = Credentials.fromJson(readTextFile(path));
    if (credentials.isExpired && !credentials.canRefresh) {
      log.error("Pub's authorization to upload packages has expired and "
          "can't be automatically refreshed.");
      return null; // null means re-authorize.
    }

    return credentials;
  } catch (e) {
    // Don't print the error message itself here. I might be leaking data about
    // credentials.
    log.error('Warning: could not load the saved OAuth2 credentials.\n'
        'Obtaining new credentials...');
    return null; // null means re-authorize.
  }
}

/// Save the user's OAuth2 credentials to the in-memory cache and the
/// filesystem.
void _saveCredentials(Credentials credentials) {
  log.fine('Saving OAuth2 credentials.');
  _credentials = credentials;
  final credentialsPath = _credentialsFile();
  if (credentialsPath != null) {
    ensureDir(p.dirname(credentialsPath));
    writeTextFile(credentialsPath, credentials.toJson(), dontLogContents: true);
  }
}

/// The path to the file in which the user's OAuth2 credentials are stored.
///
/// Returns `null` if there is no good place for the file.
String? _credentialsFile() {
  final configDir = dartConfigDir;
  return configDir == null ? null : p.join(configDir, 'pub-credentials.json');
}

/// Gets the user to authorize pub as a client of pub.dev via oauth2.
///
/// Returns a Future that completes to a fully-authorized [_Client].
Future<_Client> _authorize() async {
  final grant = _AuthorizationCodeGrant(
    _identifier, _authorizationEndpoint, tokenEndpoint,
    secret: _secret,
    // Google's OAuth2 API doesn't support basic auth.
    basicAuth: false,
    httpClient: _retryHttpClient,
  );

  // Spin up a one-shot HTTP server to receive the authorization code from the
  // Google OAuth2 server via redirect. This server will close itself as soon as
  // the code is received.
  final completer = Completer<_Client>();
  final server = await bindServer('localhost', 0);
  shelf_io.serveRequests(server, (request) {
    if (request.url.path.isNotEmpty) {
      return shelf.Response.notFound('Invalid URI.');
    }

    log.message('Authorization received, processing...');
    final queryString = request.url.query;
    // Closing the server here is safe, since it will wait until the response
    // is sent to actually shut down.
    server.close();
    completer
        .complete(grant.handleAuthorizationResponse(queryToMap(queryString)));

    return shelf.Response.found('https://pub.dev/authorized');
  });

  final authUrl = grant.getAuthorizationUrl(
    Uri.parse('http://localhost:${server.port}'),
    scopes: _scopes,
  );

  log.message(
      'Pub needs your authorization to upload packages on your behalf.\n'
      'In a web browser, go to $authUrl\n'
      'Then click "Allow access".\n\n'
      'Waiting for your authorization...');

  final client = await completer.future;
  log.message('Successfully authorized.\n');
  return client;
}

/// Fetches Google's OpenID Connect Discovery document and parses the JSON
/// response body into a [Map].
///
/// See https://developers.google.com/identity/openid-connect/openid-connect#discovery
Future<Map> fetchOidcDiscoveryDocument() async {
  final discoveryResponse = await retryForHttp(
      'fetching Google\'s OpenID Connect Discovery document', () async {
    final request = http.Request('GET', _oidcDiscoveryDocumentEndpoint);
    return await globalHttpClient.fetch(request);
  });
  return parseJsonResponse(discoveryResponse);
}

// The following code originates in package:oauth2.
// TODO(sigurdm): simplify to only do what we need.

/// A class for obtaining credentials via an [authorization code grant][].
///
/// This method of authorization involves sending the resource owner to the
/// authorization server where they will authorize the client. They're then
/// redirected back to your server, along with an authorization code. This is
/// used to obtain [Credentials] and create a fully-authorized [_Client].
///
/// To use this class, you must first call [getAuthorizationUrl] to get the URL
/// to which to redirect the resource owner. Then once they've been redirected
/// back to your application, call [handleAuthorizationResponse] or
/// [handleAuthorizationCode] to process the authorization server's response and
/// construct a [_Client].
///
/// [authorization code grant]: http://tools.ietf.org/html/draft-ietf-oauth-v2-31#section-4.1
class _AuthorizationCodeGrant {
  /// The function used to parse parameters from a host's response.
  final _GetParameters _getParameters;

  /// The client identifier for this client.
  ///
  /// The authorization server will issue each client a separate client
  /// identifier and secret, which allows the server to tell which client is
  /// accessing it. Some servers may also have an anonymous identifier/secret
  /// pair that any client may use.
  ///
  /// This is usually global to the program using this library.
  final String identifier;

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

  /// A URL provided by the authorization server that serves as the base for the
  /// URL that the resource owner will be redirected to to authorize this
  /// client.
  ///
  /// This will usually be listed in the authorization server's OAuth2 API
  /// documentation.
  final Uri authorizationEndpoint;

  /// A URL provided by the authorization server that this library uses to
  /// obtain long-lasting credentials.
  ///
  /// This will usually be listed in the authorization server's OAuth2 API
  /// documentation.
  final Uri tokenEndpoint;

  /// Callback to be invoked whenever the credentials are refreshed.
  ///
  /// This will be passed as-is to the constructed [_Client].
  final _CredentialsRefreshedCallback? _onCredentialsRefreshed;

  /// Whether to use HTTP Basic authentication for authorizing the client.
  final bool _basicAuth;

  /// A [String] used to separate scopes; defaults to `" "`.
  final String _delimiter;

  /// The HTTP client used to make HTTP requests.
  http.Client? _httpClient;

  /// The URL to which the resource owner will be redirected after they
  /// authorize this client with the authorization server.
  Uri? _redirectEndpoint;

  /// The scopes that the client is requesting access to.
  List<String>? _scopes;

  /// An opaque string that users of this library may specify that will be
  /// included in the response query parameters.
  String? _stateString;

  /// The current state of the grant object.
  _State _state = _State.initial;

  /// Allowed characters for generating the _codeVerifier
  static const String _charset =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

  /// The PKCE code verifier. Will be generated if one is not provided in the
  /// constructor.
  final String _codeVerifier;

  /// Creates a new grant.
  ///
  /// If [basicAuth] is `true` (the default), the client credentials are sent to
  /// the server using using HTTP Basic authentication as defined in [RFC 2617].
  /// Otherwise, they're included in the request body. Note that the latter form
  /// is not recommended by the OAuth 2.0 spec, and should only be used if the
  /// server doesn't support Basic authentication.
  ///
  /// [RFC 2617]: https://tools.ietf.org/html/rfc2617
  ///
  /// [httpClient] is used for all HTTP requests made by this grant, as well as
  /// those of the [_Client] is constructs.
  ///
  /// [onCredentialsRefreshed] will be called by the constructed [_Client]
  /// whenever the credentials are refreshed.
  ///
  /// [codeVerifier] String to be used as PKCE code verifier. If none is
  /// provided a random codeVerifier will be generated.
  /// The codeVerifier must meet requirements specified in [RFC 7636].
  ///
  /// [RFC 7636]: https://tools.ietf.org/html/rfc7636#section-4.1
  ///
  /// The scope strings will be separated by the provided [delimiter]. This
  /// defaults to `" "`, the OAuth2 standard, but some APIs (such as Facebook's)
  /// use non-standard delimiters.
  ///
  /// By default, this follows the OAuth2 spec and requires the server's
  /// responses to be in JSON format. However, some servers return non-standard
  /// response formats, which can be parsed using the [getParameters] function.
  ///
  /// This function is passed the `Content-Type` header of the response as well
  /// as its body as a UTF-8-decoded string. It should return a map in the same
  /// format as the [standard JSON response][].
  ///
  /// [standard JSON response]: https://tools.ietf.org/html/rfc6749#section-5.1
  _AuthorizationCodeGrant(
    this.identifier,
    this.authorizationEndpoint,
    this.tokenEndpoint, {
    this.secret,
    String? delimiter,
    bool basicAuth = true,
    http.Client? httpClient,
    _CredentialsRefreshedCallback? onCredentialsRefreshed,
    Map<String, dynamic> Function(MediaType? contentType, String body)?
        getParameters,
    String? codeVerifier,
  })  : _basicAuth = basicAuth,
        _httpClient = httpClient ?? http.Client(),
        _delimiter = delimiter ?? ' ',
        _getParameters = getParameters ?? parseJsonParameters,
        _onCredentialsRefreshed = onCredentialsRefreshed,
        _codeVerifier = codeVerifier ?? _createCodeVerifier();

  /// Returns the URL to which the resource owner should be redirected to
  /// authorize this client.
  ///
  /// The resource owner will then be redirected to [redirect], which should
  /// point to a server controlled by the client. This redirect will have
  /// additional query parameters that should be passed to
  /// [handleAuthorizationResponse].
  ///
  /// The specific permissions being requested from the authorization server may
  /// be specified via [scopes]. The scope strings are specific to the
  /// authorization server and may be found in its documentation. Note that you
  /// may not be granted access to every scope you request; you may check the
  /// [Credentials.scopes] field of [_Client.credentials] to see which scopes you
  /// were granted.
  ///
  /// An opaque [state] string may also be passed that will be present in the
  /// query parameters provided to the redirect URL.
  ///
  /// It is a [StateError] to call this more than once.
  Uri getAuthorizationUrl(
    Uri redirect, {
    Iterable<String>? scopes,
    String? state,
  }) {
    if (_state != _State.initial) {
      throw StateError('The authorization URL has already been generated.');
    }
    _state = _State.awaitingResponse;

    final scopeList = scopes?.toList() ?? <String>[];
    final codeChallenge = base64Url
        .encode(sha256.convert(ascii.encode(_codeVerifier)).bytes)
        .replaceAll('=', '');

    _redirectEndpoint = redirect;
    _scopes = scopeList;
    _stateString = state;
    final parameters = {
      'response_type': 'code',
      'client_id': identifier,
      'redirect_uri': redirect.toString(),
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
    };

    if (state != null) parameters['state'] = state;
    if (scopeList.isNotEmpty) parameters['scope'] = scopeList.join(_delimiter);

    return _addQueryParameters(authorizationEndpoint, parameters);
  }

  /// Processes the query parameters added to a redirect from the authorization
  /// server.
  ///
  /// Note that this "response" is not an HTTP response, but rather the data
  /// passed to a server controlled by the client as query parameters on the
  /// redirect URL.
  ///
  /// It is a [StateError] to call this more than once, to call it before
  /// [getAuthorizationUrl] is called, or to call it after
  /// [handleAuthorizationCode] is called.
  ///
  /// Throws [FormatException] if [parameters] is invalid according to the
  /// OAuth2 spec or if the authorization server otherwise provides invalid
  /// responses. If `state` was passed to [getAuthorizationUrl], this will throw
  /// a [FormatException] if the `state` parameter doesn't match the original
  /// value.
  ///
  /// Throws [_AuthorizationException] if the authorization fails.
  Future<_Client> handleAuthorizationResponse(
    Map<String, String> parameters,
  ) async {
    if (_state == _State.initial) {
      throw StateError('The authorization URL has not yet been generated.');
    } else if (_state == _State.finished) {
      throw StateError('The authorization code has already been received.');
    }
    _state = _State.finished;

    if (_stateString != null) {
      if (!parameters.containsKey('state')) {
        throw FormatException('Invalid OAuth response for '
            '"$authorizationEndpoint": parameter "state" expected to be '
            '"$_stateString", was missing.');
      } else if (parameters['state'] != _stateString) {
        throw FormatException('Invalid OAuth response for '
            '"$authorizationEndpoint": parameter "state" expected to be '
            '"$_stateString", was "${parameters['state']}".');
      }
    }

    if (parameters.containsKey('error')) {
      final description = parameters['error_description'];
      final uriString = parameters['error_uri'];
      final uri = uriString == null ? null : Uri.parse(uriString);
      throw _AuthorizationException(parameters['error']!, description, uri);
    } else if (!parameters.containsKey('code')) {
      throw FormatException('Invalid OAuth response for '
          '"$authorizationEndpoint": did not contain required parameter '
          '"code".');
    }

    return _handleAuthorizationCode(parameters['code']);
  }

  /// Processes an authorization code directly.
  ///
  /// Usually [handleAuthorizationResponse] is preferable to this method, since
  /// it validates all of the query parameters. However, some authorization
  /// servers allow the user to copy and paste an authorization code into a
  /// command-line application, in which case this method must be used.
  ///
  /// It is a [StateError] to call this more than once, to call it before
  /// [getAuthorizationUrl] is called, or to call it after
  /// [handleAuthorizationCode] is called.
  ///
  /// Throws [FormatException] if the authorization server provides invalid
  /// responses while retrieving credentials.
  ///
  /// Throws [_AuthorizationException] if the authorization fails.
  Future<_Client> handleAuthorizationCode(String authorizationCode) async {
    if (_state == _State.initial) {
      throw StateError('The authorization URL has not yet been generated.');
    } else if (_state == _State.finished) {
      throw StateError('The authorization code has already been received.');
    }
    _state = _State.finished;

    return _handleAuthorizationCode(authorizationCode);
  }

  /// This works just like [handleAuthorizationCode], except it doesn't validate
  /// the state beforehand.
  Future<_Client> _handleAuthorizationCode(String? authorizationCode) async {
    final startTime = DateTime.now();

    final headers = <String, String>{};

    final body = {
      'grant_type': 'authorization_code',
      'code': authorizationCode,
      'redirect_uri': _redirectEndpoint.toString(),
      'code_verifier': _codeVerifier,
    };

    final secret = this.secret;
    if (_basicAuth && secret != null) {
      headers['Authorization'] = _basicAuthHeader(identifier, secret);
    } else {
      // The ID is required for this request any time basic auth isn't being
      // used, even if there's no actual client authentication to be done.
      body['client_id'] = identifier;
      if (secret != null) body['client_secret'] = secret;
    }

    final response =
        await _httpClient!.post(tokenEndpoint, headers: headers, body: body);

    final credentials = _handleAccessTokenResponse(
      response,
      tokenEndpoint,
      startTime,
      _scopes,
      _delimiter,
      getParameters: _getParameters,
    );
    return _Client(
      credentials,
      identifier: identifier,
      secret: secret,
      basicAuth: _basicAuth,
      httpClient: _httpClient,
      onCredentialsRefreshed: _onCredentialsRefreshed,
    );
  }

  // Randomly generate a 128 character string to be used as the PKCE code
  // verifier.
  static String _createCodeVerifier() => List.generate(
        128,
        (i) => _charset[Random.secure().nextInt(_charset.length)],
      ).join();

  /// Closes the grant and frees its resources.
  ///
  /// This will close the underlying HTTP client, which is shared by the
  /// [_Client] created by this grant, so it's not safe to close the grant and
  /// continue using the client.
  void close() {
    _httpClient?.close();
    _httpClient = null;
  }
}

/// States that [_AuthorizationCodeGrant] can be in.
enum _State {
  initial('initial'),
  awaitingResponse('awaiting response'),
  finished('finished');

  final String _name;

  const _State(this._name);

  @override
  String toString() => _name;
}

/// An exception raised when OAuth2 authorization fails.
class _AuthorizationException implements Exception {
  /// The name of the error.
  ///
  /// Possible names are enumerated in [the spec][].
  ///
  /// [the spec]: http://tools.ietf.org/html/draft-ietf-oauth-v2-31#section-5.2
  final String error;

  /// The description of the error, provided by the server.
  ///
  /// May be `null` if the server provided no description.
  final String? description;

  /// A URL for a page that describes the error in more detail, provided by the
  /// server.
  ///
  /// May be `null` if the server provided no URL.
  final Uri? uri;

  /// Creates an AuthorizationException.
  _AuthorizationException(this.error, this.description, this.uri);

  /// Provides a string description of the AuthorizationException.
  @override
  String toString() {
    var header = 'OAuth authorization error ($error)';
    if (description != null) {
      header = '$header: $description';
    } else if (uri != null) {
      header = '$header: $uri';
    }
    return '$header.';
  }
}

/// An OAuth2 client.
///
/// This acts as a drop-in replacement for an [http.Client], while sending
/// OAuth2 authorization credentials along with each request.
///
/// The client also automatically refreshes its credentials if possible. When it
/// makes a request, if its credentials are expired, it will first refresh them.
/// This means that any request may throw an [_AuthorizationException] if the
/// refresh is not authorized for some reason, a [FormatException] if the
/// authorization server provides ill-formatted responses, or an
/// [_ExpirationException] if the credentials are expired and can't be refreshed.
///
/// The client will also throw an [_AuthorizationException] if the resource
/// server returns a 401 response with a WWW-Authenticate header indicating that
/// the current credentials are invalid.
///
/// If you already have a set of [Credentials], you can construct a [_Client]
/// directly. However, in order to first obtain the credentials, you must
/// authorize. At the time of writing, the only authorization method this
/// library supports is [_AuthorizationCodeGrant].
class _Client extends http.BaseClient {
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
  final _CredentialsRefreshedCallback? _onCredentialsRefreshed;

  /// Whether to use HTTP Basic authentication for authorizing the client.
  final bool _basicAuth;

  /// The underlying HTTP client.
  http.Client? _httpClient;

  /// Creates a new client from a pre-existing set of credentials.
  ///
  /// When authorizing a client for the first time, you should use
  /// [_AuthorizationCodeGrant] or [_resourceOwnerPasswordGrant] instead of
  /// constructing a [_Client] directly.
  ///
  /// [httpClient] is the underlying client that this forwards requests to after
  /// adding authorization credentials to them.
  ///
  /// Throws an [ArgumentError] if [secret] is passed without [identifier].
  _Client(
    this._credentials, {
    this.identifier,
    this.secret,
    _CredentialsRefreshedCallback? onCredentialsRefreshed,
    bool basicAuth = true,
    http.Client? httpClient,
  })  : _basicAuth = basicAuth,
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
      if (!credentials.canRefresh) throw _ExpirationException(credentials);
      await refreshCredentials();
    }

    request.headers['authorization'] = 'Bearer ${credentials.accessToken}';
    final response = await _httpClient!.send(request);

    if (response.statusCode != 401) return response;
    if (!response.headers.containsKey('www-authenticate')) return response;

    List<AuthenticationChallenge> challenges;
    try {
      challenges = AuthenticationChallenge.parseHeader(
        response.headers['www-authenticate']!,
      );
    } on FormatException {
      return response;
    }

    final challenge = challenges
        .firstWhereOrNull((challenge) => challenge.scheme == 'bearer');
    if (challenge == null) return response;

    final params = challenge.parameters;
    if (!params.containsKey('error')) return response;

    throw _AuthorizationException(
      params['error']!,
      params['error_description'],
      params['error_uri'] == null ? null : Uri.parse(params['error_uri']!),
    );
  }

  /// A [Future] used to track whether [refreshCredentials] is running.
  Future<Credentials>? _refreshingFuture;

  /// Explicitly refreshes this client's credentials. Returns this client.
  ///
  /// This will throw a [StateError] if the [Credentials] can't be refreshed, an
  /// [_AuthorizationException] if refreshing the credentials fails, or a
  /// [FormatException] if the authorization server returns invalid responses.
  ///
  /// You may request different scopes than the default by passing in
  /// [newScopes]. These must be a subset of the scopes in the
  /// [Credentials.scopes] field of [_Client.credentials].
  Future<_Client> refreshCredentials([List<String>? newScopes]) async {
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

/// Type of the callback when credentials are refreshed.
typedef _CredentialsRefreshedCallback = void Function(Credentials);

/// Credentials that prove that a client is allowed to access a resource on the
/// resource owner's behalf.
///
/// These credentials are long-lasting and can be safely persisted across
/// multiple runs of the program.
///
/// Many authorization servers will attach an expiration date to a set of
/// credentials, along with a token that can be used to refresh the credentials
/// once they've expired. The [_Client] will automatically refresh its
/// credentials when necessary. It's also possible to explicitly refresh them
/// via [_Client.refreshCredentials] or [Credentials.refresh].
///
/// Note that a given set of credentials can only be refreshed once, so be sure
/// to save the refreshed credentials for future use.
class Credentials {
  /// A [String] used to separate scopes; defaults to `" "`.
  String _delimiter;

  /// The token that is sent to the resource server to prove the authorization
  /// of a client.
  final String accessToken;

  /// The token that is sent to the authorization server to refresh the
  /// credentials.
  ///
  /// This may be `null`, indicating that the credentials can't be refreshed.
  final String? refreshToken;

  /// The token that is received from the authorization server to enable
  /// End-Users to be Authenticated, contains Claims, represented as a
  /// JSON Web Token (JWT).
  ///
  /// This may be `null`, indicating that the 'openid' scope was not
  /// requested (or not supported).
  ///
  /// [spec]: https://openid.net/specs/openid-connect-core-1_0.html#IDToken
  final String? idToken;

  /// The URL of the authorization server endpoint that's used to refresh the
  /// credentials.
  ///
  /// This may be `null`, indicating that the credentials can't be refreshed.
  final Uri? tokenEndpoint;

  /// The specific permissions being requested from the authorization server.
  ///
  /// The scope strings are specific to the authorization server and may be
  /// found in its documentation.
  final List<String>? scopes;

  /// The date at which these credentials will expire.
  ///
  /// This is likely to be a few seconds earlier than the server's idea of the
  /// expiration date.
  final DateTime? expiration;

  /// The function used to parse parameters from a host's response.
  final _GetParameters _getParameters;

  /// Whether or not these credentials have expired.
  ///
  /// Note that it's possible the credentials will expire shortly after this is
  /// called. However, since the client's expiration date is kept a few seconds
  /// earlier than the server's, there should be enough leeway to rely on this.
  bool get isExpired {
    final expiration = this.expiration;
    return expiration != null && DateTime.now().isAfter(expiration);
  }

  /// Whether it's possible to refresh these credentials.
  bool get canRefresh => refreshToken != null && tokenEndpoint != null;

  /// Creates a new set of credentials.
  ///
  /// This class is usually not constructed directly; rather, it's accessed via
  /// [_Client.credentials] after a [_Client] is created by
  /// [_AuthorizationCodeGrant]. Alternately, it may be loaded from a serialized
  /// form via [Credentials.fromJson].
  ///
  /// The scope strings will be separated by the provided [delimiter]. This
  /// defaults to `" "`, the OAuth2 standard, but some APIs (such as Facebook's)
  /// use non-standard delimiters.
  ///
  /// By default, this follows the OAuth2 spec and requires the server's
  /// responses to be in JSON format. However, some servers return non-standard
  /// response formats, which can be parsed using the [getParameters] function.
  ///
  /// This function is passed the `Content-Type` header of the response as well
  /// as its body as a UTF-8-decoded string. It should return a map in the same
  /// format as the [standard JSON response][].
  ///
  /// [standard JSON response]: https://tools.ietf.org/html/rfc6749#section-5.1
  Credentials(
    this.accessToken, {
    this.refreshToken,
    this.idToken,
    this.tokenEndpoint,
    Iterable<String>? scopes,
    this.expiration,
    String? delimiter,
    Map<String, dynamic> Function(MediaType? mediaType, String body)?
        getParameters,
  })  : scopes = UnmodifiableListView(
          // Explicitly type-annotate the list literal to work around
          // sdk#24202.
          scopes == null ? <String>[] : scopes.toList(),
        ),
        _delimiter = delimiter ?? ' ',
        _getParameters = getParameters ?? parseJsonParameters;

  /// Loads a set of credentials from a JSON-serialized form.
  ///
  /// Throws a [FormatException] if the JSON is incorrectly formatted.
  factory Credentials.fromJson(String json) {
    void validate(bool condition, String message) {
      if (condition) return;
      throw FormatException('Failed to load credentials: $message.\n\n$json');
    }

    dynamic parsed;
    try {
      parsed = jsonDecode(json);
    } on FormatException {
      validate(false, 'invalid JSON');
    }

    validate(parsed is Map, 'was not a JSON map');

    parsed = parsed as Map;
    validate(
      parsed.containsKey('accessToken'),
      'did not contain required field "accessToken"',
    );
    validate(
      parsed['accessToken'] is String,
      'required field "accessToken" was not a string, was '
      '${parsed["accessToken"]}',
    );

    for (var stringField in ['refreshToken', 'idToken', 'tokenEndpoint']) {
      final value = parsed[stringField];
      validate(
        value == null || value is String,
        'field "$stringField" was not a string, was "$value"',
      );
    }

    final scopes = parsed['scopes'];
    validate(
      scopes == null || scopes is List,
      'field "scopes" was not a list, was "$scopes"',
    );

    final tokenEndpoint = parsed['tokenEndpoint'];
    Uri? tokenEndpointUri;
    if (tokenEndpoint != null) {
      tokenEndpointUri = Uri.parse(tokenEndpoint as String);
    }

    var expiration = parsed['expiration'];
    DateTime? expirationDateTime;
    if (expiration != null) {
      validate(
        expiration is int,
        'field "expiration" was not an int, was "$expiration"',
      );
      expiration = expiration as int;
      expirationDateTime = DateTime.fromMillisecondsSinceEpoch(expiration);
    }

    return Credentials(
      parsed['accessToken'] as String,
      refreshToken: parsed['refreshToken'] as String?,
      idToken: parsed['idToken'] as String?,
      tokenEndpoint: tokenEndpointUri,
      scopes: (scopes as List).map((scope) => scope as String),
      expiration: expirationDateTime,
    );
  }

  /// Serializes a set of credentials to JSON.
  ///
  /// Nothing is guaranteed about the output except that it's valid JSON and
  /// compatible with [Credentials.toJson].
  String toJson() => jsonEncode({
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'idToken': idToken,
        'tokenEndpoint': tokenEndpoint?.toString(),
        'scopes': scopes,
        'expiration': expiration?.millisecondsSinceEpoch,
      });

  /// Returns a new set of refreshed credentials.
  ///
  /// See [_Client.identifier] and [_Client.secret] for explanations of those
  /// parameters.
  ///
  /// You may request different scopes than the default by passing in
  /// [newScopes]. These must be a subset of [scopes].
  ///
  /// This throws an [ArgumentError] if [secret] is passed without [identifier],
  /// a [StateError] if these credentials can't be refreshed, an
  /// [_AuthorizationException] if refreshing the credentials fails, or a
  /// [FormatException] if the authorization server returns invalid responses.
  Future<Credentials> refresh({
    String? identifier,
    String? secret,
    Iterable<String>? newScopes,
    bool basicAuth = true,
    http.Client? httpClient,
  }) async {
    var scopes = this.scopes;
    if (newScopes != null) scopes = newScopes.toList();
    scopes ??= [];
    httpClient ??= http.Client();

    if (identifier == null && secret != null) {
      throw ArgumentError('secret may not be passed without identifier.');
    }

    final startTime = DateTime.now();
    final tokenEndpoint = this.tokenEndpoint;
    if (refreshToken == null) {
      throw StateError("Can't refresh credentials without a refresh "
          'token.');
    } else if (tokenEndpoint == null) {
      throw StateError("Can't refresh credentials without a token "
          'endpoint.');
    }

    final headers = <String, String>{};

    final body = {'grant_type': 'refresh_token', 'refresh_token': refreshToken};
    if (scopes.isNotEmpty) body['scope'] = scopes.join(_delimiter);

    if (basicAuth && secret != null) {
      headers['Authorization'] = _basicAuthHeader(identifier!, secret);
    } else {
      if (identifier != null) body['client_id'] = identifier;
      if (secret != null) body['client_secret'] = secret;
    }

    final response =
        await httpClient.post(tokenEndpoint, headers: headers, body: body);
    final credentials = _handleAccessTokenResponse(
      response,
      tokenEndpoint,
      startTime,
      scopes,
      _delimiter,
      getParameters: _getParameters,
    );

    // The authorization server may issue a new refresh token. If it doesn't,
    // we should re-use the one we already have.
    if (credentials.refreshToken != null) return credentials;
    return Credentials(
      credentials.accessToken,
      refreshToken: refreshToken,
      idToken: credentials.idToken,
      tokenEndpoint: credentials.tokenEndpoint,
      scopes: credentials.scopes,
      expiration: credentials.expiration,
    );
  }
}

/// An exception raised when attempting to use expired OAuth2 credentials.
class _ExpirationException implements Exception {
  /// The expired credentials.
  final Credentials credentials;

  /// Creates an ExpirationException.
  _ExpirationException(this.credentials);

  /// Provides a string description of the ExpirationException.
  @override
  String toString() =>
      "OAuth2 credentials have expired and can't be refreshed.";
}

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
Credentials _handleAccessTokenResponse(
  http.Response response,
  Uri tokenEndpoint,
  DateTime startTime,
  List<String>? scopes,
  String delimiter, {
  Map<String, dynamic> Function(MediaType? contentType, String body)?
      getParameters,
}) {
  getParameters ??= parseJsonParameters;

  try {
    if (response.statusCode != 200) {
      _handleErrorResponse(response, tokenEndpoint, getParameters);
    }

    final contentTypeString = response.headers['content-type'];
    if (contentTypeString == null) {
      throw const FormatException('Missing Content-Type string.');
    }

    final parameters =
        getParameters(MediaType.parse(contentTypeString), response.body);

    for (var requiredParameter in ['access_token', 'token_type']) {
      if (!parameters.containsKey(requiredParameter)) {
        throw FormatException(
          'did not contain required parameter "$requiredParameter"',
        );
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
        '"$tokenEndpoint": unknown token type "${parameters['token_type']}"',
      );
    }

    var expiresIn = parameters['expires_in'];
    if (expiresIn != null) {
      if (expiresIn is String) {
        try {
          expiresIn = double.parse(expiresIn).toInt();
        } on FormatException {
          throw FormatException(
            'parameter "expires_in" could not be parsed as in, was: "$expiresIn"',
          );
        }
      } else if (expiresIn is! int) {
        throw FormatException(
          'parameter "expires_in" was not an int, was: "$expiresIn"',
        );
      }
    }

    for (var name in ['refresh_token', 'id_token', 'scope']) {
      final value = parameters[name];
      if (value != null && value is! String) {
        throw FormatException(
          'parameter "$name" was not a string, was "$value"',
        );
      }
    }

    final scope = parameters['scope'] as String?;
    if (scope != null) scopes = scope.split(delimiter);

    final expiration = expiresIn == null
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
  http.Response response,
  Uri tokenEndpoint,
  _GetParameters getParameters,
) {
  // OAuth2 mandates a 400 or 401 response code for access token error
  // responses. If it's not a 400 reponse, the server is either broken or
  // off-spec.
  if (response.statusCode != 400 && response.statusCode != 401) {
    var reason = '';
    final reasonPhrase = response.reasonPhrase;
    if (reasonPhrase != null && reasonPhrase.isNotEmpty) {
      reason = ' $reasonPhrase';
    }
    throw FormatException('OAuth request for "$tokenEndpoint" failed '
        'with status ${response.statusCode}$reason.\n\n${response.body}');
  }

  final contentTypeString = response.headers['content-type'];
  final contentType =
      contentTypeString == null ? null : MediaType.parse(contentTypeString);

  final parameters = getParameters(contentType, response.body);

  if (!parameters.containsKey('error')) {
    throw const FormatException('did not contain required parameter "error"');
  } else if (parameters['error'] is! String) {
    throw FormatException('required parameter "error" was not a string, was '
        '"${parameters["error"]}"');
  }

  for (var name in ['error_description', 'error_uri']) {
    final value = parameters[name];

    if (value != null && value is! String) {
      throw FormatException('parameter "$name" was not a string, was "$value"');
    }
  }

  final uriString = parameters['error_uri'] as String?;
  final uri = uriString == null ? null : Uri.parse(uriString);
  final description = parameters['error_description'] as String?;
  throw _AuthorizationException(
    parameters['error'] as String,
    description,
    uri,
  );
}

/// The type of a callback that parses parameters from an HTTP response.
typedef _GetParameters = Map<String, dynamic> Function(
  MediaType? contentType,
  String body,
);

/// Parses parameters from a response with a JSON body, as per the
/// [OAuth2 spec][].
///
/// [OAuth2 spec]: https://tools.ietf.org/html/rfc6749#section-5.1
Map<String, dynamic> parseJsonParameters(MediaType? contentType, String body) {
  // The spec requires a content-type of application/json, but some endpoints
  // (e.g. Dropbox) serve it as text/javascript instead.
  if (contentType == null ||
      (contentType.mimeType != 'application/json' &&
          contentType.mimeType != 'text/javascript')) {
    throw FormatException(
      'Content-Type was "$contentType", expected "application/json"',
    );
  }

  final untypedParameters = jsonDecode(body);
  if (untypedParameters is Map<String, dynamic>) {
    return untypedParameters;
  }

  throw FormatException('Parameters must be a map, was "$untypedParameters"');
}

/// Adds additional query parameters to [url], overwriting the original
/// parameters if a name conflict occurs.
Uri _addQueryParameters(Uri url, Map<String, String> parameters) => url.replace(
      queryParameters: Map.from(url.queryParameters)..addAll(parameters),
    );

String _basicAuthHeader(String identifier, String secret) {
  final userPass = '${Uri.encodeFull(identifier)}:${Uri.encodeFull(secret)}';
  return 'Basic ${base64Encode(ascii.encode(userPass))}';
}
