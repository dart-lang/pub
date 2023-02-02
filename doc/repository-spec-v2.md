Hosted Pub Repository Specification Version 2
=============================================
This document specifies the REST API that a hosted pub _package repository_ must
implement.

A package repository is a server from which packages can be downloaded,
the default package repository is `'https://pub.dev'`.
It used to be [pub.dartlang.org](https://pub.dartlang.org).

## Hosted URL
A custom package repository is identified by a _hosted-url_, like
`https://pub.dev` or `https://some-server.com/prefix/pub/`.
The _hosted-url_ always includes protocol `http://` or `https://`.
For the purpose of this specification the _hosted-url_ should always be
normalized such that it doesn't end with a slash (`/`). As all URL end-points
described in this specification includes slash prefix.

For the remainder of this specification the placeholder `<hosted-url>` will be
used in place of a _hosted-url_ such as:
 * `https://pub.dev`
 * `https://some-server.com/prefix/pub`
 * `https://pub.other-server.com/prefix`
 * `http://localhost:8080`

A _hosted-url_ is **not allowed** to contain:
 * [_user-info_](https://datatracker.ietf.org/doc/html/rfc3986#section-3.2.1),
   example: `https://user:passwd@host.com`.
 * [query-string](https://datatracker.ietf.org/doc/html/rfc3986#section-3.4),
   example: `https://host.com/?key=value`.
 * [fragment](https://datatracker.ietf.org/doc/html/rfc3986#section-3.5),
   example: `https://host.com/#fragment`.


## Custom Package Repository in `pubspec.yaml`
A package be published to a custom _package repository_ by overwriting the
`publish_to` key in `pubspec.yaml`, illustrated as follows:
```yaml
name: mypkg
version: 1.0.0
publish_to: <hosted-url>
```

When taking dependency upon a package from a custom _package repository_ the
dependency must be specified as follows:
```yaml
name: myapp
dependencies:
  mypkg:
    version: ^1.0.0
    hosted:
      url: <hosted-url>
      name: mypkg
```


## Forward Compatibility
The `dart pub` client will always include an `Accept` header specifying the API
version requested, as follows:

 * `Accept: application/vnd.pub.v2+json`

To ensure forward compatibility all API requests should include an `Accept`
header which specifies the version of the API being used. This allows future
versions of the API to change responses.

Clients are strongly encouraged to specify an `Accept` header. But for
compatiblity will probably want to assume API version `2`,
if no `Accept` header is specified.


## Metadata headers
The `dart pub` client will attach a `User-Agent` header as follows:

 * `User-Agent: Dart pub <sdk-version>`

Custom clients are strongly encouraged to specify a custom `User-Agent` that
allows _package repository operators_ to identify which client a request is
coming from. Including a URL allowing operators to reach owners/authors of the
client is good practice.

 * `User-Agent: my-pub-bot/1.2.3 (+https://github.com/organization/<repository>)`

The `User-Agent` header also allows package repository to determine how many
different clients would be affected by an API change.


## Retrying with Exponential Backoff
The `dart pub` client will retry failed requests with
[exponential backoff](https://en.wikipedia.org/wiki/Exponential_backoff).
This aims to increase robustness against intermittent network issues, while not
overloading servers that are partially failing.

Clients are strongly encouraged to employ exponential backoff starting at 200ms,
400ms, etc. stopping after 5-7 retries. Excessive retries can have a negative impact
on servers and network performance.


## Rejecting Requests
The `dart pub` client will in many cases to display error messages when given a
response as follows:

```http
HTTP/1.1 4XX Bad Request
Content-Type: application/vnd.pub.v2+json
{
  "error": {
    "code": "<code>",
    "message": "<message>",
  },
}
```

The `<message>` is intended to be a brief human readable explanation of what
when wrong and why the request failed. The `<code>` is a text string intended to
allow clients to handle special cases without using regular expression to
parse the `<message>`.


## Authentication
The `dart pub` client allows users to save an opaque `<token>` for each
`<hosted-url>`. When the `dart pub` client makes a request to a `<hosted-url>`
for which it has a `<token>` stored, it will attach an `Authorization` header
as follows:

 * `Authorization: Bearer <token>`

Tokens can be added to `dart pub` client using the command:

 * `dart pub token add <hosted-url>`

This command will prompt the user for the `<token>` on stdin, reducing the risk
that the `<token>` is accidentally stored in shell history. For security reasons
authentication can only be used when `<hosted-url>` uses HTTPS. For further
details on token management see: `dart pub token --help`.

The tokens are inserted verbatim in the header, therefore they have to adhere to
 https://www.rfc-editor.org/rfc/rfc6750#section-2.1. This means they must match
 the regex: `^[a-zA-Z0-9._~+/=-]+$`.


### Missing Authentication or Invalid Token
If the server requires authentication and the request does not carry an
`Authorization` header, or the token in the `Authorization` header is invalid
or expired, the server must respond:

```http
HTTP/1.1 401 Unauthorized
WWW-Authenticate: Bearer realm="pub", message="<message>"
```

If the `dart pub` client receives a `401` response and the `dart pub` client has
a token for the given `<hosted-url>`, then the `dart pub` client knows for sure
that the token it has stored for the given `<hosted-url>` is invalid.
Hence, the `dart pub` client shall remove the token from local configuration.
Hence, a server shall not send `401` in case where a token is valid, but does
not have permissions to access the package in question.

When receiving a `401` response the `dart pub` client shall:
 * Abort the current operation (exiting non-zero),
 * Delete any token it may have stored for the given `<hosted-url>`,
 * Inform the user that authentication is required,
 * Print the `<message>` provided by the server.

The `<message>` allows a custom _package server_ to inform the user how a token
may be obtained.
For example, a server might specify a URL from which tokens can be created, as
illustrated below:

```http
GET /packages/mypkg HTTP/1.1
HOST: pub.example.com
User-Agent: Dart pub 2.15.0
Accept: application/vnd.pub.v2+json


HTTP/1.1 401 Unauthorized
WWW-Authenticate: Bearer realm="pub", message="Obtain a token from https://pub.example.com/manage-tokens"
```

The `dart pub` will display the `message` in the terminal, so the user can
discover that they need to navigate to `https://pub.example.com/manage-tokens`. 
Once the user opens this URL in the browser, the server is then free to ask the
user to sign-in using any browser-based authentication mechanism. Once signed-in
the server can allow the user to create a token and tell the user to copy/paste
this into stdin for `dart pub token add pub.example.com`.

Package server authors are advised to consider security practices such as:
 * Prevent a token from being returned again after its initial creation.
 * Associate names with tokens (so users can remember what computer they
   create the token for).
 * Record last used date-time for each token.
 * Expire tokens not frequently used.
 * Token rotation through forced expiration.


### Insufficient Permissions

If the server requires authorization and the request carries an `Authorization`
header with a valid token, but this token authenticates the client as a user
that does not have permissions to access the given resource the server must
respond:

```http
HTTP/1.1 403 Forbidden
WWW-Authenticate: Bearer realm="pub", message="<message>"
```

This behaves the same as `401` with the exception that the token will not be
automatically deleted from local configuration by the `dart pub` client. This
makes sense if the token is valid, but doesn't have sufficient permissions.

The `<message>` allows a custom package repository to indicate how sufficient
permissions can be granted. Depending on how permissions are managed on the
server, this could work in many different ways.


## List all versions of a package

**GET** `<hosted-url>/api/packages/<package>`

**Headers:**
* `Accept: application/vnd.pub.v2+json`

**Response**
* `Content-Type: application/vnd.pub.v2+json`

```js
{
  "name": "<package>",
  "isDiscontinued": true || false, /* optional field, false if omitted */
  "replacedBy": "<package>", /* optional field, if isDiscontinued == true */
  "latest": {
    "version": "<version>",
    "retracted": true || false, /* optional field, false if omitted */
    "archive_url": "https://.../archive.tar.gz",
    "archive_sha256": "95cbaad58e2cf32d1aa852f20af1fcda1820ead92a4b1447ea7ba1ba18195d27"
    "pubspec": {
      /* pubspec contents as JSON object */
    }
  },
  "versions": [
    {
      "version": "<package>",
      "retracted": true || false, /* optional field, false if omitted */
      "archive_url": "https://.../archive.tar.gz",
      "archive_sha256": "95cbaad58e2cf32d1aa852f20af1fcda1820ead92a4b1447ea7ba1ba18195d27"
      "pubspec": {
        /* pubspec contents as JSON object */
      }
    },
    /* additional versions */
  ]
}
```

To fetch the package archive an HTTP `GET` request **following redirects** must
be made to the URL given as `archive_url`.
The response (after following redirects) must be a gzipped TAR archive.

The `archive_url` may be temporary and is allowed to include query-string
parameters. This allows for the server to return signed-URLs for S3, GCS or
other blob storage service. If temporary URLs are returned it is wise to not set
expiration to less than 25 minutes (to allow for retries and clock drift).

The `archive_sha256` should be the hex-encoded sha256 checksum of the file at
archive_url. It is an optional field that allows the pub client to verify the
integrity of the downloaded archive.

The `archive_sha256` also provides an easy way for clients to detect if
something has changed on the server. In the absense of this field the client can
still download the archive to obtain a checksum and detect changes to the
archive.

If `<hosted-url>` for the server returning `archive_url` is a prefix of
`archive_url`, then the `Authorization: Bearer <token>` is also included when
`archive_url` is requested. Example: if `https://pub.example.com/path` returns
an `archive_url = 'https://pub.example.com/path/...'` then the request for
`https://pub.example.com/path/...` will include `Authorization` header.
This would however, not be case if the same server returned
`archive_url = 'https://pub.example.com/blob/...'`.


## Publishing Packages

**GET** `<hosted-url>/api/packages/versions/new`

**Headers:**
* `Accept: application/vnd.pub.v2+json`
* `Authorization: Bearer <token>` (required)

**Response**
* `Content-Type: application/vnd.pub.v2+json`

```js
{
  "url": "<multipart-upload-url>",
  "fields": {
    "<field-1>": "<value-1>",
    "<field-2>": "<value-2>",
    ...,
    "<field-N>": "<value-N>",
  },
}
```

To publish a package a HTTP `GET` request for
`<hosted-url>/api/packages/versions/new` is made. This request returns an
`<multipart-upload-url>` and a dictionary of fields. To upload the package
archive a multi-part `POST` request is made to `<multipart-upload-url>` with
fields and the field `file` containing the gzipped tar archive.

```http
POST <path(multipart-upload-url)> HTTP/1.1
Host: <host(multipart-upload-url)>
Content-Length: <length>
Content-Type: multipart/form-data; boundary=<boundary>

--<boundary>
Content-Disposition: form-data; name="<urlencode(field-1)>"
Content-Type: text/plain; charset=utf-8
Content-Transfer-Encoding: binary

<value-1>
--<boundary>
Content-Disposition: form-data; name="<urlencode(field-2)>"
Content-Type: text/plain; charset=utf-8
Content-Transfer-Encoding: binary

<value-2>
...
--<boundary>
Content-Disposition: form-data; name="<urlencode(field-N)>"
Content-Type: text/plain; charset=utf-8
Content-Transfer-Encoding: binary

<value-N>
--<boundary>
Content-Type: application/octet-stream
Content-Disposition: form-data; name="file"; filename="package.tar.gz"

<gzipped archieve>
```

The above `POST` request to `<multipart-upload-url>` should respond as follows:

```http
HTTP/1.1 204 No Content
Location: <finalize-upload-url>
```

The client shall then issue a `GET` request to `<finalize-upload-url>`. As with
`archive_url` the client will only attach an `Authorization` if the
`<hosted-url>` is a prefix of `<finalize-upload-url>`. If the server wants to
accepts the uploaded package the server should respond:

```http
HTTP/1.1 200 Ok
Content-Type: application/vnd.pub.v2+json
{
  "success": {
    "message": "<message>",
  },
}
```

The server is allowed to consider the publishing incomplete until the `GET`
request for `<finalize-upload-url>` has been issued. Once this request has
succeeded the package is considered successfully published. If the server has
caches that need to expire before newly published packages becomes available,
or it has other out-of-band approvals that need to be given it's reasonable to
inform the user about this in the `<message>`.

If the server does not want to accept the uploaded package, it can respond:
```http
HTTP/1.1 400 Bad Request
Content-Type: application/vnd.pub.v2+json
{
  "error": {
    "code": "<code>",
    "message": "<message>",
  },
}
```

This can be used to forbid git-dependencies in published packages, limit the
archive size, or enforce any other repository specific constraints.

This upload flow allows for archives to be uploaded directly to a signed POST
URL for [S3](https://docs.aws.amazon.com/AmazonS3/latest/userguide/HTTPPOSTExamples.html),
[GCS](https://cloud.google.com/storage/docs/xml-api/post-object-forms) or
similar blob storage service. Both the
`<multipart-upload-url>` and `<finalize-upload-url>` is allowed to contain
query-string parameters, and both of these URLs need only be temporary.


------------

## (Deprecated) Inspect a specific version of a package


**Deprecated** as of Dart 2.8, use "List all versions of a package" instead.
Servers should still support this end-point for compatibility with older `pub` clients.

**GET** `<hosted-url>/api/packages/<package>/versions/<version>`

**Headers:**
* `Accept: application/vnd.pub.v2+json`

**Response**
* `Content-Type: application/vnd.pub.v2+json`

```js
{
  "version": "1.1.0",
  "archive_url": "https://.../archive.tar.gz",
  "pubspec": {
    /* pubspec contents as JSON object */
  }
}
```


## (Deprecated) Download a specific version of a package

**Deprecated** as of Dart 2.8, use the `archive_url` returned from the "List all versions of a package".
Servers should still support this end-point for compatibility with older `pub` clients.

**GET** `<hosted-url>/packages/<package>/versions/<version>.tar.gz`

**Headers**
* `Accept: application/octet-stream` (optional)

**Response** (typically through a ´30x` redirect)
* `Content-Type: application/octet-stream`

**Important:** The server MAY redirect the client to a different URL, clients
MUST support redirects.

