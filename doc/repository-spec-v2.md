# Hosted Pub Repository Specification Version 2

This document specifies the REST API that a hosted pub package repository must
implement.

A hosted pub package repository is a server from which packages can be
downloaded, the default public pub server is `'https://pub.dartlang.org'`.
This can be overwritten in the `dependencies` of a `pubspec.yaml` or specified
with the environment variable `PUB_HOSTED_URL`. In the rest of this document we
shall refer to the base URL as `PUB_HOSTED_URL`.

## Authentication

All relevant commands will add an `Authorization` header with `Bearer <token>` value if
specified through the `pub login <server>` command. If not specified all calls will have
no `Authorization` header for both get and post commands.

To add a token for the server:

`pub login <server> [--token <secret>]`

The `<secret>` can be set trough the command-line or if not set, pub will prompt to enter a value.
You can use an environment variable as `secret`. In that case you need to set `'$YOUR_ENV'` (note the quotes).
Environment variables are the preferred solution. They can also be used in CI environments.

To remove a token (or all) you can:

`pub logout [<server>] [--all]`

## Forward Compatibility

To ensure forward compatibility API requests should carry an
`Accept: application/vnd.pub.v2+json` header. As future versions of the API
may have different responses.

## Fetching Packages

The following API end-points MUST be supported by a hosted pub package
repository.

**Optional headers** used for popularity metrics.

- `X-Pub-OS: windows | macos | linux | ...`
- `X-Pub-Command: get | upgrade | ...`
- `X-Pub-Session-ID: <UUID>`
- `X-Pub-Reason: direct | dev`
- `X-Pub-Environment: ...`
- `User-Agent: ...`

### List all versions of a package

**GET** `<PUB_HOSTED_URL>/api/packages/<PACKAGE>`

**Headers:**

- `Accept: application/vnd.pub.v2+json`

**Response**

- `Content-Type: application/vnd.pub.v2+json`

```js
{
  "name": "<PACKAGE>",
  "latest": {
    "version": "<VERSION>",
    "archive_url": "https://.../archive.tar.gz",
    "pubspec": {
      /* pubspec contents as JSON object */
    }
  },
  "versions": [
    {
      "version": "<VERSION>",
      "archive_url": "https://.../archive.tar.gz",
      "pubspec": {
        /* pubspec contents as JSON object */
      }
    },
    /* additional versions */
  ]
}
```

To fetch the package archive an HTTP `GET` request _following retries_ must be
made to the URL given as `archive_url`. The response (after following redirects)
must be a gzipped TAR archive.

### (Deprecated) Inspect a specific version of a package

**Deprecated** as of Dart 2.8, use "List all versions of a package" instead.
Servers should still support this end-point for compatibility with older `pub` clients.

**GET** `<PUB_HOSTED_URL>/api/packages/<PACKAGE>/versions/<VERSION>`

**Headers:**

- `Accept: application/vnd.pub.v2+json`

**Response**

- `Content-Type: application/vnd.pub.v2+json`

```js
{
  "version": "1.1.0",
  "archive_url": "https://.../archive.tar.gz",
  "pubspec": {
    /* pubspec contents as JSON object */
  }
}
```

### (Deprecated) Download a specific version of a package

**Deprecated** as of Dart 2.8, use the `archive_url` returned from the "List all versions of a package".
Servers should still support this end-point for compatibility with older `pub` clients.

**GET** `<PUB_HOSTED_URL>/packages/<PACKAGE>/versions/<VERSION>.tar.gz`

**Headers**

- `Accept: application/octet-stream` (optional)

**Response** (typically through a ´30x` redirect)

- `Content-Type: application/octet-stream`

**Important:** The server MAY redirect the client to a different URL, clients
MUST support redirects.
