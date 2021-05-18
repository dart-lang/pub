Authenticating with Hosted Pub Repositories Proposal
====================================================

This document specifies how the REST API could be authenticated with the pub CLI
tool.

## Requesting authentication

If the repository requires special authentication to access resources or upload
new packages, it has to respond with `401 Unauthorized` status code with `WWW-Authenticate` header. This header should specify authentication method that should be used to gain access to the resource.

WWW-Authenticate header syntax:

```plain
WWW-Authenticate: <type> realm=<realm>[, charset="UTF-8"]
```

Pub CLI will only support **Basic** and **Bearer** authentication methods by
default.

## Authentication flow

After receiving `WWW-Authenticate` header, pub CLI will prompt user for
the credentials like this:

```plain
user@machine$ pub get
Please enter required credentials to authenticate with "https://myserver.com"
hosted repository.

Username: bob
Password: password

Please enter required credentials to authenticate with "https://pub.example.com"
hosted repository.

Bearer token: 8O868XsPJm-F5nyEzXfa9-YWFvrd3O8r
```

After providing credentials, the client will send those credentials to the
server in `Authorization` header.


```dart
// Bearer authentication
{ 'Autorization': 'Bearer $token' }

// Basic authentication
{ 'Autorization': 'Basic ' + base64('$username:$password') }
```

### Explicit authentication

Users can also explicitly define authentication credentials even before server
asks for it using a modified **pub login** command. By default if no argument is
presented, **pub login** will behave as previously: authenticate with Google.
But if you you specify server to login, it will try to authenticate with the
given server instead.

```plain
pub login https://myspuberver.dev
```

To discover authentication method, client will send **GET** request to `/login`
endpoint. This endpoint should be authenticated by the server as well as other
endpoints. The client might use this endpoint to:

1. Validate cached credentials when needed
2. Discover authentication method by sending unauthenticated requests

## Storing credentials

Hosted Pub Repository authentication credentials will be stored on json file
named `hosted.credentials.json` located in cache root directory. Authentication
details will be stored at this file as json values while their keys will be URLs
of the server (`PUB_HOSTED_URL`).

```json
{
  "https://myserver.com": {
    "method": "Basic",
    "credentials": {
      "username": "bob",
      "password": "password"
    }
  },
  "https://pub.example.com": {
    "method": "Bearer",
    "credentials": {
      "token": "8O868XsPJm-F5nyEzXfa9-YWFvrd3O8r"
    }
  }
}
```

This model of storing credentials allows us to extend support to new
authentication methods in future.

## References

- [RFC7235 - 401 Unauthorized](https://datatracker.ietf.org/doc/html/rfc7235#section-3.1)
- [RFC7235 - WWW-Authenticate](https://datatracker.ietf.org/doc/html/rfc7235#section-4.1)
- [MDN - WWW-Authenticate](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/WWW-Authenticate)