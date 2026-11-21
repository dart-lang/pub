# Hosted repository authentication helpers

A developer registers a local program for a repository:

    dart pub token add https://packages.example/org/feed/ --auth-helper=/opt/bin/onepub --auth-helper-arg=_pub-auth

Pub saves the command in `pub-tokens.json`. Here it runs `/opt/bin/onepub`
with the argument `_pub-auth`. Each `--auth-helper-arg` adds one argument.
Use an absolute executable path (a native .exe on Windows) and keep secrets
out of arguments. Only the user can register a helper. Installing a dependency
cannot choose a program to run.

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

For `action: acquire`, pub sends the package name and the operation.
A `read` covers version listings, advisories and downloads. A `publish`
also includes the version and a description of each file being uploaded:

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
publish file requires a new acquisition. Only the registration is saved.

### Authenticate a request

For a bearer token (`tokenType: Bearer`, the default), pub sends the token in
the Authorization header. For a DPoP token, each protected request also needs
a fresh signature from the key bound to the token. Pub sends the helper
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
