// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:oauth2/oauth2.dart';
import 'package:path/path.dart' as path;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'http.dart';
import 'io.dart';
import 'log.dart' as log;
import 'system_cache.dart';
import 'utils.dart';

/// The pub client's OAuth2 identifier.
const _identifier = '818368855108-8grd2eg9tj9f38os6f1urbcvsq399u8n.apps.'
    'googleusercontent.com';

/// The pub client's OAuth2 secret.
///
/// This isn't actually meant to be kept a secret.
const _secret = 'SWeqj8seoJW0w7_CpEPFLX0K';

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
  var tokenEndpoint = Platform.environment['_PUB_TEST_TOKEN_ENDPOINT'];
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
Credentials _credentials;

/// Delete the cached credentials, if they exist.
void _clearCredentials(SystemCache cache) {
  _credentials = null;
  var credentialsFile = _credentialsFile(cache);
  if (entryExists(credentialsFile)) deleteEntry(credentialsFile);
}

/// Try to delete the cached credentials.
void logout(SystemCache cache) {
  var credentialsFile = _credentialsFile(cache);
  if (entryExists(_credentialsFile(cache))) {
    log.message('Logging out of pub.dev.');
    log.message('Deleting $credentialsFile');
    _clearCredentials(cache);
  } else {
    log.message(
        'No existing credentials file $credentialsFile. Cannot log out.');
  }
}

/// Asynchronously passes an OAuth2 [Client] to [fn], and closes the client when
/// the [Future] returned by [fn] completes.
///
/// This takes care of loading and saving the client's credentials, as well as
/// prompting the user for their authorization. It will also re-authorize and
/// re-run [fn] if a recoverable authorization error is detected.
Future<T> withClient<T>(SystemCache cache, Future<T> Function(Client) fn) {
  return _getClient(cache).then((client) {
    return fn(client).whenComplete(() {
      client.close();
      // Be sure to save the credentials even when an error happens.
      _saveCredentials(cache, client.credentials);
    });
  }).catchError((error) {
    if (error is ExpirationException) {
      log.error("Pub's authorization to upload packages has expired and "
          "can't be automatically refreshed.");
      return withClient(cache, fn);
    } else if (error is AuthorizationException) {
      var message = 'OAuth2 authorization failed';
      if (error.description != null) {
        message = '$message (${error.description})';
      }
      log.error('$message.');
      _clearCredentials(cache);
      return withClient(cache, fn);
    } else {
      throw error;
    }
  });
}

/// Gets a new OAuth2 client.
///
/// If saved credentials are available, those are used; otherwise, the user is
/// prompted to authorize the pub client.
Future<Client> _getClient(SystemCache cache) async {
  var credentials = _loadCredentials(cache);
  if (credentials == null) return await _authorize();

  var client = Client(credentials,
      identifier: _identifier,
      secret: _secret,
      // Google's OAuth2 API doesn't support basic auth.
      basicAuth: false,
      httpClient: httpClient);
  _saveCredentials(cache, client.credentials);
  return client;
}

/// Loads the user's OAuth2 credentials from the in-memory cache or the
/// filesystem if possible.
///
/// If the credentials can't be loaded for any reason, the returned [Future]
/// completes to `null`.
Credentials _loadCredentials(SystemCache cache) {
  log.fine('Loading OAuth2 credentials.');

  try {
    if (_credentials != null) return _credentials;

    var path = _credentialsFile(cache);
    if (!fileExists(path)) return null;

    var credentials = Credentials.fromJson(readTextFile(path));
    if (credentials.isExpired && !credentials.canRefresh) {
      log.error("Pub's authorization to upload packages has expired and "
          "can't be automatically refreshed.");
      return null; // null means re-authorize.
    }

    return credentials;
  } catch (e) {
    log.error('Warning: could not load the saved OAuth2 credentials: $e\n'
        'Obtaining new credentials...');
    return null; // null means re-authorize.
  }
}

/// Save the user's OAuth2 credentials to the in-memory cache and the
/// filesystem.
void _saveCredentials(SystemCache cache, Credentials credentials) {
  log.fine('Saving OAuth2 credentials.');
  _credentials = credentials;
  var credentialsPath = _credentialsFile(cache);
  ensureDir(path.dirname(credentialsPath));
  writeTextFile(credentialsPath, credentials.toJson(), dontLogContents: true);
}

/// The path to the file in which the user's OAuth2 credentials are stored.
String _credentialsFile(SystemCache cache) =>
    path.join(cache.rootDir, 'credentials.json');

/// Gets the user to authorize pub as a client of pub.dev via oauth2.
///
/// Returns a Future that completes to a fully-authorized [Client].
Future<Client> _authorize() async {
  var grant =
      AuthorizationCodeGrant(_identifier, _authorizationEndpoint, tokenEndpoint,
          secret: _secret,
          // Google's OAuth2 API doesn't support basic auth.
          basicAuth: false,
          httpClient: httpClient);

  // Spin up a one-shot HTTP server to receive the authorization code from the
  // Google OAuth2 server via redirect. This server will close itself as soon as
  // the code is received.
  var completer = Completer();
  var server = await bindServer('localhost', 0);
  shelf_io.serveRequests(server, (request) {
    if (request.url.path.isNotEmpty) {
      return shelf.Response.notFound('Invalid URI.');
    }

    log.message('Authorization received, processing...');
    var queryString = request.url.query ?? '';

    // Closing the server here is safe, since it will wait until the response
    // is sent to actually shut down.
    server.close();
    completer
        .complete(grant.handleAuthorizationResponse(queryToMap(queryString)));

    return shelf.Response.found('https://pub.dev/authorized');
  });

  var authUrl = grant.getAuthorizationUrl(
      Uri.parse('http://localhost:${server.port}'),
      scopes: _scopes);

  log.message(
      'Pub needs your authorization to upload packages on your behalf.\n'
      'In a web browser, go to $authUrl\n'
      'Then click "Allow access".\n\n'
      'Waiting for your authorization...');

  var client = await completer.future;
  log.message('Successfully authorized.\n');
  return client;
}
