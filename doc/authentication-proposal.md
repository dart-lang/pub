Authenticating with Hosted Pub Repositories Proposal
====================================================

This document specifies how the REST API could be authenticated with the pub CLI
tool.

This proposal is mostly based on
[RFC7235](https://datatracker.ietf.org/doc/html/rfc7235) - HTTP Authentication
specifications. This ensures exists un-protected endpoints could be protected
just by setting up reverse proxies like NGINX, Apache, Traefik, which already
supports this specifications.

## Requesting authentication

If the repository requires special authentication to access resources or upload
new packages, it has to respond with `401 Unauthorized` status code with
`WWW-Authenticate` header. This header should specify authentication method that
should be used to gain access to the resource.

WWW-Authenticate header syntax:

```plain
WWW-Authenticate: <type> [realm=<realm>][, charset="UTF-8"]
```

> `realm` parameter is completely optional, and will not be used by pub.
> You can read more about this parameter here:
> https://datatracker.ietf.org/doc/html/rfc7235#section-2.2

Pub CLI currently only support **Bearer** authentication methods.

### Login / logout

Users can login to 3rd party hosted pub server using **pub login** command like
that:

```plain
pub login --server https://myspuberver.dev --token xxxxxxxxxx
```

`--server` is base url of the pub server and `--token` is bearer token for the
authentication. If the server option is not provided, **pub login** will behave
like previous versions - will try authenticating with Google account.

Just like this, **pub logout** will also support 3rd party hosted pub server
de-authentication. If you provide `--server` option to the command it will
simply remove saved credentials for the server. If not, it will remove Google
account credentials.

## Storing credentials

Hosted Pub Repository authentication credentials will be stored on json file
named `tokens.json` located in cache root directory. Authentication details will
be stored at this file as json values while their keys will be URLs of the
server (`PUB_HOSTED_URL`).

```json
{
  "version": "1.0",
  "hosted": [
    {
      "url": "https://myserver.com",
      "credential": {
        "kind": "Basic",
        "username": "bob",
        "password": "password"
      }
    },
    {
      "url": "https://pub.example.com",
      "credential": {
        "kind": "Bearer",
        "token": "8O868XsPJm-F5nyEzXfa9-YWFvrd3O8r"
      }
    }
  ]
}
```

This model of storing credentials allows us to extend support for new
authentication methods in future.

## References

- [RFC7235](https://datatracker.ietf.org/doc/html/rfc7235)
- [MDN - WWW-Authenticate](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/WWW-Authenticate)
