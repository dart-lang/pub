// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'package:meta/meta.dart';

/// [AuthConfig] is used for setting up parameters required
/// to establish an OAUTH2 authentitcation. This class will be used with
/// [AuthorizationCodeGrant] from `oath2` library.
class AuthConfig {
  const AuthConfig({
    @required this.authorizationEndpoint,
    @required this.identifier,
    @required this.scopes,
    @required this.secret,
    @required this.tokenEndpoint,
    this.useIdToken = false,
    @required this.redirectOnAuthorization,
  });

  /// The URL of the authorization server endpoint that's used to authorize the
  /// credentials.
  ///
  /// This may be `null`, indicating that the credentials can't be authenticated.
  final Uri authorizationEndpoint;

  /// The URL of the authorization server endpoint that's used to refresh the
  /// credentials.
  ///
  /// This may be `null`, indicating that the credentials can't be refreshed.
  final Uri tokenEndpoint;

  /// The specific permissions being requested from the authorization server.
  ///
  /// The scope strings are specific to the authorization server and may be
  /// found in its documentation.
  final List<String> scopes;

  /// OAUTH server secret
  final String secret;

  /// OAUTH server client identifier.
  final String identifier;

  /// Use Id Token instead of access token in Authorization header
  final bool useIdToken;

  /// Url to redirect on successful authorization
  final String redirectOnAuthorization;

  /// Loads a set of auth configuration from a JSON-serialized form.
  ///
  /// Throws a [FormatException] if the JSON is incorrectly formatted.
  factory AuthConfig.fromJson(String json) {
    void validate(condition, message) {
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

    for (var stringField in [
      'identifier',
      'authorizationEndpoint',
      'tokenEndpoint',
      'secret',
      'redirectOnAuthorization'
    ]) {
      var value = parsed[stringField];
      validate(parsed.containsKey(stringField),
          'did not contain required field "$stringField"');
      validate(value == null || value is String,
          'field "$stringField" was not a string, was "$value"');
    }

    var mapScopes = parsed['scopes'];
    validate(mapScopes == null || mapScopes is List,
        'field "scopes" was not a list, was "$mapScopes"');

    var mapTokenEndpoint = parsed['tokenEndpoint'];
    if (mapTokenEndpoint != null) {
      mapTokenEndpoint = Uri.parse(mapTokenEndpoint);
    }

    var mapAuthorizationEndpoint = parsed['authorizationEndpoint'];
    if (mapAuthorizationEndpoint != null) {
      mapAuthorizationEndpoint = Uri.parse(mapAuthorizationEndpoint);
    }

    return AuthConfig(
        authorizationEndpoint: mapAuthorizationEndpoint,
        tokenEndpoint: mapTokenEndpoint,
        identifier: parsed['identifier'],
        secret: parsed['secret'],
        redirectOnAuthorization: parsed['redirectOnAuthorization'],
        scopes: [for (dynamic scope in mapScopes) scope.toString()],
        useIdToken: parsed['useIdToken'] == null
            ? false
            : parsed['useIdToken'].toString().toLowerCase() == 'true');
  }

  /// Map representation of [AuthConfig].
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'authorizationEndpoint': authorizationEndpoint.path,
      'tokenEndpoint': tokenEndpoint.path,
      'identifier': identifier,
      'secret': secret,
      'redirectOnAuthorization': redirectOnAuthorization,
      'scopes': scopes,
      'useIdToken': useIdToken
    };
  }
}
