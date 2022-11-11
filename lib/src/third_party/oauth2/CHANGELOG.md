# 2.0.1

* Handle `expires_in` when encoded as string.
* Populate the pubspec `repository` field.
* Increase the minimum Dart SDK to `2.17.0`.

# 2.0.0

* Migrate to null safety.

# 1.6.3

* Added optional `codeVerifier` parameter to `AuthorizationCodeGrant` constructor.

# 1.6.1

* Added fix to make sure that credentials are only refreshed once when multiple calls are made.

# 1.6.0

* Added PKCE support to `AuthorizationCodeGrant`.

# 1.5.0

* Added support for `clientCredentialsGrant`.

# 1.4.0

* OpenID's id_token treated.

# 1.3.0

* Added `onCredentialsRefreshed` option when creating `Client` objects.

# 1.2.3

* Support the latest `package:http` release.

# 1.2.2

* Allow the stable 2.0 SDK.

# 1.2.1

* Updated SDK version to 2.0.0-dev.17.0

# 1.2.0

* Add a `getParameter()` parameter to `new AuthorizationCodeGrant()`, `new
  Credentials()`, and `resourceOwnerPasswordGrant()`. This controls how the
  authorization server's response is parsed for servers that don't provide the
  standard JSON response.

# 1.1.1

* `resourceOwnerPasswordGrant()` now properly uses its HTTP client for requests
  made by the OAuth2 client it returns.

# 1.1.0

* Add a `delimiter` parameter to `new AuthorizationCodeGrant()`, `new
  Credentials()`, and `resourceOwnerPasswordGrant()`. This controls the
  delimiter between scopes, which some authorization servers require to be
  different values than the specified `' '`.

# 1.0.2

* Fix all strong-mode warnings.

* Support `crypto` 1.0.0.

* Support `http_parser` 3.0.0.

# 1.0.1

* Support `http_parser` 2.0.0.

# 1.0.0

## Breaking changes

* Requests that use client authentication, such as the
  `AuthorizationCodeGrant`'s access token request and `Credentials`' refresh
  request, now use HTTP Basic authentication by default. This form of
  authentication is strongly recommended by the OAuth 2.0 spec. The new
  `basicAuth` parameter may be set to `false` to force form-based authentication
  for servers that require it.

* `new AuthorizationCodeGrant()` now takes `secret` as an optional named
  argument rather than a required argument. This matches the OAuth 2.0 spec,
  which says that a client secret is only required for confidential clients.

* `new Client()` and `Credentials.refresh()` now take both `identifier` and
  `secret` as optional named arguments rather than required arguments. This
  matches the OAuth 2.0 spec, which says that the server may choose not to
  require client authentication for some flows.

* `new Credentials()` now takes named arguments rather than optional positional
  arguments.

## Non-breaking changes

* Added a `resourceOwnerPasswordGrant` method.

* The `scopes` argument to `AuthorizationCodeGrant.getAuthorizationUrl()` and
  `new Credentials()` and the `newScopes` argument to `Credentials.refresh` now
  take an `Iterable` rather than just a `List`.

* The `scopes` argument to `AuthorizationCodeGrant.getAuthorizationUrl()` now
  defaults to `null` rather than `const []`.

# 0.9.3

* Update the `http` dependency.

* Since `http` 0.11.0 now works in non-`dart:io` contexts, `oauth2` does as
  well.

# 0.9.2

* Expand the dependency on the HTTP package to include 0.10.x.

* Add a README file.
