# Hosted repository authentication helpers

A developer registers a local program for a repository:

    dart pub token add https://packages.example/org/feed/ --auth-helper=/opt/bin/repo-helper --auth-helper-arg=token

Pub saves the command in `pub-tokens.json`. Here it runs `/opt/bin/repo-helper`
with the argument `token`. Each `--auth-helper-arg` adds one argument.
Use an absolute executable path (a native .exe on Windows) and keep secrets
out of arguments.

Pub matches the full repository URL, including its case-sensitive path. It
sends credentials only within that repository on the same origin. Keep
protected download endpoints under that path.

## Helper protocol, version 1

Pub starts the helper in its installation directory. It sends one UTF-8 JSON
object on stdin, closes stdin, and expects one JSON object on stdout and an
exit status of zero. The helper must finish within 30 seconds and return at
most 64 KiB. Pub discards stderr and excludes helper output from error messages.

Every request includes `protocolVersion: 1`, `repository`, `action`, and
`interactive: false`. The helper must run without prompting. If sign-in, MFA
or a key unlock requires a person, the helper exits unsuccessfully. The user
completes that step separately and reruns pub.

### Obtain a token

When pub asks the helper for a token to look up or download a package, it
includes the package name. Pub sends `action: acquire` and `operation: read`
for version listings, security advisories and downloads. For `operation: publish`,
it also includes the version and a description of each file being uploaded:

    "archive": {"length": 18240, "sha256": "<digest of the .tar.gz file>"},
    "attestations": {"length": 412, "sha256": "<digest of the attestation file>"}

Each length is in bytes. Each digest is the lowercase hex SHA-256 of the
exact bytes pub sends. Pub omits `attestations` when there is no attestation
file. The repository can authorise this set of files and check them before
accepting the release.

The helper returns an access token, its UTC expiry and its type:

    {"token":"example","expiresAt":"2030-01-01T12:00:00Z","tokenType":"DPoP"}

Pub keeps the token in memory until expiry or rejection. Concurrent requests
with the same repository and operation details share it. A change to either
publish file requires a new acquisition.

### Authenticate a request

The repository decides what a client must present to access a package. The
helper tells pub which token it obtained using `tokenType`. With `Bearer`
(the default), pub sends the token in the Authorization header. With `DPoP`,
the repository also checks a fresh signature on each request. Someone who
copies the token alone cannot produce that signature.

To get the signature, pub sends the helper
`action: prove`, the token, HTTP method, target URI without query or fragment,
and the repository's nonce if supplied. The helper returns a signed JWT in
`proof`, including the token hash and any supplied nonce.

A repository can require a nonce by rejecting the request with HTTP 401,
`WWW-Authenticate: DPoP error="use_dpop_nonce"` and a `DPoP-Nonce` header.
Pub passes the nonce to the helper and retries the rejected HTTP step once
with a fresh proof. A successful response can supply the next nonce. Pub
keeps it scoped to that repository. A second challenge ends the operation.
An ordinary 401 clears the cached token and preserves the registration.
The helper handles challenges from its token issuer separately.
[DPoP specification](https://www.rfc-editor.org/rfc/rfc9449.html#section-9)

### Publishing and storage

The file descriptions work with today's multipart upload. The separate
[upload proposal](https://github.com/dart-lang/pub/pull/4960) would also
let a repository check them before issuing upload instructions. When using
that proposed flow, file transfers must use the storage headers supplied by
the repository. Adding helper credentials could overwrite a storage signature,
even on the same host. An authentication failure must end the operation or
use the nonce retry above. It must never trigger a fallback to legacy publishing.

Pub.dev needs no server change for a private repository to use helpers.
