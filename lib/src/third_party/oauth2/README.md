[![Dart CI](https://github.com/dart-lang/oauth2/actions/workflows/test-package.yml/badge.svg)](https://github.com/dart-lang/oauth2/actions/workflows/test-package.yml)
[![pub package](https://img.shields.io/pub/v/oauth2.svg)](https://pub.dev/packages/oauth2)
[![package publisher](https://img.shields.io/pub/publisher/oauth2.svg)](https://pub.dev/packages/oauth2/publisher)

A client library for authenticating with a remote service via OAuth2 on behalf
of a user, and making authorized HTTP requests with the user's OAuth2
credentials.

## About OAuth2

OAuth2 allows a client (the program using this library) to access and manipulate
a resource that's owned by a resource owner (the end user) and lives on a remote
server. The client directs the resource owner to an authorization server
(usually but not always the same as the server that hosts the resource), where
the resource owner tells the authorization server to give the client an access
token. This token serves as proof that the client has permission to access
resources on behalf of the resource owner.

OAuth2 provides several different methods for the client to obtain
authorization. At the time of writing, this library only supports the
[Authorization Code Grant][authorizationCodeGrantSection],
[Client Credentials Grant][clientCredentialsGrantSection] and
[Resource Owner Password Grant][resourceOwnerPasswordGrantSection] flows, but
more may be added in the future.

## Authorization Code Grant

**Resources:** [Class summary][authorizationCodeGrantMethod],
[OAuth documentation][authorizationCodeGrantDocs]

```dart
import 'dart:io';

import 'package:oauth2/oauth2.dart' as oauth2;

// These URLs are endpoints that are provided by the authorization
// server. They're usually included in the server's documentation of its
// OAuth2 API.
final authorizationEndpoint =
    Uri.parse('http://example.com/oauth2/authorization');
final tokenEndpoint = Uri.parse('http://example.com/oauth2/token');

// The authorization server will issue each client a separate client
// identifier and secret, which allows the server to tell which client
// is accessing it. Some servers may also have an anonymous
// identifier/secret pair that any client may use.
//
// Note that clients whose source code or binary executable is readily
// available may not be able to make sure the client secret is kept a
// secret. This is fine; OAuth2 servers generally won't rely on knowing
// with certainty that a client is who it claims to be.
final identifier = 'my client identifier';
final secret = 'my client secret';

// This is a URL on your application's server. The authorization server
// will redirect the resource owner here once they've authorized the
// client. The redirection will include the authorization code in the
// query parameters.
final redirectUrl = Uri.parse('http://my-site.com/oauth2-redirect');

/// A file in which the users credentials are stored persistently. If the server
/// issues a refresh token allowing the client to refresh outdated credentials,
/// these may be valid indefinitely, meaning the user never has to
/// re-authenticate.
final credentialsFile = File('~/.myapp/credentials.json');

/// Either load an OAuth2 client from saved credentials or authenticate a new
/// one.
Future<oauth2.Client> createClient() async {
  var exists = await credentialsFile.exists();

  // If the OAuth2 credentials have already been saved from a previous run, we
  // just want to reload them.
  if (exists) {
    var credentials =
        oauth2.Credentials.fromJson(await credentialsFile.readAsString());
    return oauth2.Client(credentials, identifier: identifier, secret: secret);
  }

  // If we don't have OAuth2 credentials yet, we need to get the resource owner
  // to authorize us. We're assuming here that we're a command-line application.
  var grant = oauth2.AuthorizationCodeGrant(
      identifier, authorizationEndpoint, tokenEndpoint,
      secret: secret);

  // A URL on the authorization server (authorizationEndpoint with some additional
  // query parameters). Scopes and state can optionally be passed into this method.
  var authorizationUrl = grant.getAuthorizationUrl(redirectUrl);

  // Redirect the resource owner to the authorization URL. Once the resource
  // owner has authorized, they'll be redirected to `redirectUrl` with an
  // authorization code. The `redirect` should cause the browser to redirect to
  // another URL which should also have a listener.
  //
  // `redirect` and `listen` are not shown implemented here. See below for the
  // details.
  await redirect(authorizationUrl);
  var responseUrl = await listen(redirectUrl);

  // Once the user is redirected to `redirectUrl`, pass the query parameters to
  // the AuthorizationCodeGrant. It will validate them and extract the
  // authorization code to create a new Client.
  return await grant.handleAuthorizationResponse(responseUrl.queryParameters);
}

void main() async {
  var client = await createClient();

  // Once you have a Client, you can use it just like any other HTTP client.
  print(await client.read('http://example.com/protected-resources.txt'));

  // Once we're done with the client, save the credentials file. This ensures
  // that if the credentials were automatically refreshed while using the
  // client, the new credentials are available for the next run of the
  // program.
  await credentialsFile.writeAsString(client.credentials.toJson());
}
```

<details>
  <summary>Click here to learn how to implement `redirect` and `listen`.</summary>

--------------------------------------------------------------------------------

There is not a universal example for implementing `redirect` and `listen`,
because different options exist for each platform.

For Flutter apps, there's two popular approaches:

1.  Launch a browser using [url_launcher][] and listen for a redirect using
    [uni_links][].

    ```dart
      if (await canLaunch(authorizationUrl.toString())) {
        await launch(authorizationUrl.toString()); }

      // ------- 8< -------

      final linksStream = getLinksStream().listen((Uri uri) async {
       if (uri.toString().startsWith(redirectUrl)) {
         responseUrl = uri;
       }
     });
    ```

1.  Launch a WebView inside the app and listen for a redirect using
    [webview_flutter][].

    ```dart
      WebView(
        javascriptMode: JavascriptMode.unrestricted,
        initialUrl: authorizationUrl.toString(),
        navigationDelegate: (navReq) {
          if (navReq.url.startsWith(redirectUrl)) {
            responseUrl = Uri.parse(navReq.url);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
        // ------- 8< -------
      );
    ```

For Dart apps, the best approach depends on the available options for accessing
a browser. In general, you'll need to launch the authorization URL through the
client's browser and listen for the redirect URL.
</details>

## Client Credentials Grant

**Resources:** [Method summary][clientCredentialsGrantMethod],
[OAuth documentation][clientCredentialsGrantDocs]

```dart
// This URL is an endpoint that's provided by the authorization server. It's
// usually included in the server's documentation of its OAuth2 API.
final authorizationEndpoint =
    Uri.parse('http://example.com/oauth2/authorization');

// The OAuth2 specification expects a client's identifier and secret
// to be sent when using the client credentials grant.
//
// Because the client credentials grant is not inherently associated with a user,
// it is up to the server in question whether the returned token allows limited
// API access.
//
// Either way, you must provide both a client identifier and a client secret:
final identifier = 'my client identifier';
final secret = 'my client secret';

// Calling the top-level `clientCredentialsGrant` function will return a
// [Client] instead.
var client = await oauth2.clientCredentialsGrant(
    authorizationEndpoint, identifier, secret);

// With an authenticated client, you can make requests, and the `Bearer` token
// returned by the server during the client credentials grant will be attached
// to any request you make.
var response =
    await client.read('https://example.com/api/some_resource.json');

// You can save the client's credentials, which consists of an access token, and
// potentially a refresh token and expiry date, to a file. This way, subsequent runs
// do not need to reauthenticate, and you can avoid saving the client identifier and
// secret.
await credentialsFile.writeAsString(client.credentials.toJson());
```

## Resource Owner Password Grant

**Resources:** [Method summary][resourceOwnerPasswordGrantMethod],
[OAuth documentation][resourceOwnerPasswordGrantDocs]

```dart
// This URL is an endpoint that's provided by the authorization server. It's
// usually included in the server's documentation of its OAuth2 API.
final authorizationEndpoint =
    Uri.parse('http://example.com/oauth2/authorization');

// The user should supply their own username and password.
final username = 'example user';
final password = 'example password';

// The authorization server may issue each client a separate client
// identifier and secret, which allows the server to tell which client
// is accessing it. Some servers may also have an anonymous
// identifier/secret pair that any client may use.
//
// Some servers don't require the client to authenticate itself, in which case
// these should be omitted.
final identifier = 'my client identifier';
final secret = 'my client secret';

// Make a request to the authorization endpoint that will produce the fully
// authenticated Client.
var client = await oauth2.resourceOwnerPasswordGrant(
    authorizationEndpoint, username, password,
    identifier: identifier, secret: secret);

// Once you have the client, you can use it just like any other HTTP client.
var result = await client.read('http://example.com/protected-resources.txt');

// Once we're done with the client, save the credentials file. This will allow
// us to re-use the credentials and avoid storing the username and password
// directly.
File('~/.myapp/credentials.json').writeAsString(client.credentials.toJson());
```

[authorizationCodeGrantDocs]: https://oauth.net/2/grant-types/authorization-code/
[authorizationCodeGrantMethod]: https://pub.dev/documentation/oauth2/latest/oauth2/AuthorizationCodeGrant-class.html
[authorizationCodeGrantSection]: #authorization-code-grant
[clientCredentialsGrantDocs]: https://oauth.net/2/grant-types/client-credentials/
[clientCredentialsGrantMethod]: https://pub.dev/documentation/oauth2/latest/oauth2/clientCredentialsGrant.html
[clientCredentialsGrantSection]: #client-credentials-grant
[resourceOwnerPasswordGrantDocs]: https://oauth.net/2/grant-types/password/
[resourceOwnerPasswordGrantMethod]: https://pub.dev/documentation/oauth2/latest/oauth2/resourceOwnerPasswordGrant.html
[resourceOwnerPasswordGrantSection]: #resource-owner-password-grant
[uni_links]: https://pub.dev/packages/uni_links
[url_launcher]: https://pub.dev/packages/url_launcher
[webview_flutter]: https://pub.dev/packages/webview_flutter
