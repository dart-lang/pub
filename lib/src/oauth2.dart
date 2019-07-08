// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:oauth2/oauth2.dart';
import 'package:path/path.dart' as path;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'bearer_token_client.dart';
import 'http.dart';
import 'io.dart';
import 'log.dart' as log;
import 'system_cache.dart';
import 'utils.dart';

/// The pub client's OAuth2 identifier.
final _identifier = '818368855108-8grd2eg9tj9f38os6f1urbcvsq399u8n.apps.'
    'googleusercontent.com';

/// The pub client's OAuth2 secret.
///
/// This isn't actually meant to be kept a secret.
final _secret = 'SWeqj8seoJW0w7_CpEPFLX0K';

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

/// An in-memory cache of the user's bearer tokens.
///
/// This should always be the same as the tokens file stored in the system
/// cache.
Map<String, String> _tokens;

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
    log.message("Logging out of pub.dartlang.org.");
    log.message("Deleting $credentialsFile");
    _clearCredentials(cache);
  } else {
    log.message(
        "No existing credentials file $credentialsFile. Cannot log out.");
  }
}

/// Asynchronously passes an OAuth2 [Client] to [fn], and closes the client when
/// the [Future] returned by [fn] completes.
///
/// This takes care of loading and saving the client's credentials, as well as
/// prompting the user for their authorization. It will also re-authorize and
/// re-run [fn] if a recoverable authorization error is detected.
Future<T> withClient<T>(
    SystemCache cache, Future<T> fn(http.BaseClient client)) {
  return _getClient(cache).then((client) {
    return fn(client).whenComplete(() {
      client.close();
      if (client is Client) {
        // Be sure to save the credentials even when an error happens.
        // Note: this is only performed for the pub.dartlang.org client.
        _saveCredentials(cache, client.credentials);
      }
    });
  }).catchError((error) {
    if (error is ExpirationException) {
      log.error("Pub's authorization to upload packages has expired and "
          "can't be automatically refreshed.");
      return withClient(cache, fn);
    } else if (error is AuthorizationException) {
      var message = "OAuth2 authorization failed";
      if (error.description != null) {
        message = "$message (${error.description})";
      }
      log.error("$message.");
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
Future<http.BaseClient> _getClient(SystemCache cache) async {
  // For any server other than pub.dartlang.org and pub.dev, we will
  // use $PUB_CACHE/tokens.json
  var pubHostedUrl =
      Platform.environment['PUB_HOSTED_URL'] ?? 'https://pub.dev';
  if (!['https://pub.dartlang.org', 'https://pub.dev'].contains(pubHostedUrl)) {
    // Pub will default to searching for an OAuth2 token in
    // $PUB_CACHE/credentials.json.
    //
    // However, if $PUB_HOSTED_URL is contained within $PUB_CACHE/tokens.json,
    // then instead opt for an HTTP client that sends the provided token
    // in the Authorization header.
    var tokens = _loadTokens(cache);
    var tokensFile = _tokensFile(cache);

    if (tokens.containsKey(pubHostedUrl)) {
      return BearerTokenClient(tokens[pubHostedUrl], httpClient);
    } else {
      // If there is no entry for the given server, prompt the user for one.
      log.message('Your \$PUB_HOSTED_URL is "$pubHostedUrl", but "$tokensFile" '
          'contains no entry for that URL.');
      var token = await prompt('Enter your token for "$pubHostedUrl"');
      // Save the new credentials.
      _saveTokens(cache, tokens..[pubHostedUrl] = token);
      return BearerTokenClient(token, httpClient);
    }
  }

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

/// Loads the user's stored bearer tokens from the in-memory cache or the
/// filesystem if possible.
///
/// If the credentials can't be loaded for any reason, the returned [Future]
/// completes to `{}`.
Map<String, String> _loadTokens(SystemCache cache) {
  String path;

  try {
    if (_tokens != null) return _tokens;

    path = _tokensFile(cache);
    if (!fileExists(path)) return {};

    var data = json.decode(readTextFile(path));
    if (data is Map<String, dynamic>) {
      // So that format errors can be caught as early as possible,
      // eagerly iterate through and cast the set of tokens, rather
      // than using a lazy alternative.
      return Map.fromEntries(
          data.entries.map((e) => MapEntry(e.key, e.value as String)));
    } else {
      log.error(
          'The format of "$path" is incorrect. It must be a map of string keys to string values.');
      return {};
    }
  } on CastError {
    var sourceOfError = path == null ? '' : '"$path"';
    log.error('The format of $sourceOfError is incorrect. '
        'It must be a map of string keys to string values, '
        'but at least one key or value was not a string.');
    return {};
  } catch (e) {
    return {};
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

/// Save the user's bearer tokens to the in-memory cache and the
/// filesystem.
void _saveTokens(SystemCache cache, Map<String, String> tokens) {
  log.fine('Saving bearer tokens.');
  _tokens = tokens;
  var encoder = JsonEncoder.withIndent('  ');
  var tokensPath = _tokensFile(cache);
  ensureDir(path.dirname(tokensPath));
  writeTextFile(tokensPath, encoder.convert(tokens), dontLogContents: true);
}

/// The path to the file in which the user's OAuth2 credentials are stored.
String _credentialsFile(SystemCache cache) =>
    path.join(cache.rootDir, 'credentials.json');

/// The path to the file in which the user's third-party Bearer tokens are stored.
String _tokensFile(SystemCache cache) =>
    path.join(cache.rootDir, 'tokens.json');

/// Gets the user to authorize pub as a client of pub.dartlang.org via oauth2.
///
/// Returns a Future that completes to a fully-authorized [Client].
Future<Client> _authorize() {
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
  bindServer('localhost', 0).then((server) {
    shelf_io.serveRequests(server, (request) {
      if (request.url.path.isNotEmpty) {
        return shelf.Response.notFound('Invalid URI.');
      }

      log.message('Authorization received, processing...');
      var queryString = request.url.query ?? '';

      // Closing the server here is safe, since it will wait until the response
      // is sent to actually shut down.
      server.close();
      chainToCompleter(
          grant.handleAuthorizationResponse(queryToMap(queryString)),
          completer);

      return shelf.Response.found('https://pub.dartlang.org/authorized');
    });

    var authUrl = grant.getAuthorizationUrl(
        Uri.parse('http://localhost:${server.port}'),
        scopes: _scopes);

    log.message(
        'Pub needs your authorization to upload packages on your behalf.\n'
        'In a web browser, go to $authUrl\n'
        'Then click "Allow access".\n\n'
        'Waiting for your authorization...');
  });

  return completer.future.then((client) {
    log.message('Successfully authorized.\n');
    return client;
  });
}
