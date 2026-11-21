# Hosted repository authentication helpers

A developer can tell pub which local program to run for credentials at a
particular repository. For example:

    dart pub token add https://packages.example/org/team/feed/ --auth-helper=/opt/bin/onepub --auth-helper-arg=_pub-auth

This saves the command in the user's `pub-tokens.json`. Pub will start
`/opt/bin/onepub` with the subcommand `_pub-auth`. Each `--auth-helper-arg`
supplies one fixed command-line argument. Pub passes those arguments directly
to the executable, preserving spaces and punctuation. Supply an absolute
executable path (a native .exe on Windows). Keep secrets out of arguments.

A dependency's `pubspec.yaml` may identify its hosted repository. Installing
that dependency cannot configure a program to run on the developer's machine.
Only the user's helper registration supplies the command. Listing, registering
or removing helpers does not run them.

Pub selects the registration for the exact canonical repository URL, including
its case-sensitive path. The repository chooses its path hierarchy. A nested
repository has its own registration. Within an operation pub sends credentials
only to endpoints beneath the selected base on the same origin. A repository
requiring proof for private downloads must keep the final protected download
endpoint in scope. An external storage URL must work without this credential.

## Running without a prompt

The same interface works in terminals, IDE background tasks and CI jobs. Pub
starts the helper in its installation directory, writes one UTF-8 JSON object
to stdin, closes stdin, and reads one JSON object from stdout. The helper must
be able to complete unattended. It may use an existing sign-in or an enrolled
key. If a browser sign-in, MFA prompt or key unlock requires a person, it must
exit unsuccessfully. The user can complete the repository's sign-in separately
and rerun pub. The helper should never open a browser or wait for keyboard
input during dependency resolution. Pub discards stderr, limits stdout to
64 KiB and gives the running helper 30 seconds. Helper output is excluded from
error messages.

## Protocol version 1

All requests contain `protocolVersion: 1`, the canonical `repository` URL,
an `action`, and `interactive: false`.

### Obtain an access token

Pub sends `action: acquire`, the operation and the package name. Each
authenticated read in pub knows the package: listing its versions, looking up
its advisories, or downloading a version. For example:

    {"protocolVersion":1,"action":"acquire","repository":"https://packages.example/org/team/feed/","interactive":false,"operation":"read","package":"widgets"}

For `operation: publish`, pub also sends the manifest version and
`archiveSha256`, the lowercase hexadecimal SHA-256 of the exact compressed
`.tar.gz` file it will upload. The repository can authorise publication of
those bytes as, for example, `widgets` version `1.2.0`. It must verify its
own permissions, manifest and digest when accepting the publication.

The helper returns an access token, its UTC expiry, and the type of credential:

    {"token":"example","expiresAt":"2030-01-01T12:00:00Z","tokenType":"DPoP"}

Pub keeps the returned **access token** in memory for the current pub process.
Concurrent requests for the same repository, operation and package context
share one acquisition. Publish context also includes version and digest.
Pub obtains another token after expiry. Only the helper registration is saved
on disk. Every request using a DPoP token gets a newly signed proof.

### Use the credential the repository issued

A bearer credential (`tokenType: Bearer`, the default) is presented in the
Authorization header. This supports repositories that accept bearer tokens,
including short-lived publication tokens restricted to a single package
upload. Anyone holding an ordinary live bearer can present it within its scope.

For a DPoP credential, the repository binds the token to a public key. Pub
requires the helper to sign every protected HTTP request using the matching
private key. A proof failure fails that request. The repository must reject a
DPoP token presented as a bearer or with an invalid proof. This lets a
repository enforce device-protected downloads while other repositories
continue using their existing authentication.

Pub sends `action: prove`, the access token, HTTP method, target URI without
query or fragment, and the repository's nonce when supplied. The helper
returns a `proof` string containing a fresh signed DPoP JWT, including the
access-token hash and the supplied nonce. Pub sends it in the DPoP header.

### Handle a server-issued challenge

A nonce is a value chosen by the repository that the helper includes in its
signature. It prevents a key holder preparing tomorrow's proofs today. A
repository enforcing this protection should reject proofs missing a currently
accepted nonce and check proof identifiers to detect replay.

1. On first contact pub can have a token but no nonce for the repository.
   It sends a signed request. A repository requiring a nonce rejects it with
   HTTP 401, `WWW-Authenticate: DPoP error="use_dpop_nonce"` and
   `DPoP-Nonce: <value>`.
2. Pub gives that value to the helper. It sends the rejected request once
   more with a fresh proof. The token stays in memory. A second challenge
   surfaces an authentication error. A publication retry recreates only the
   rejected HTTP step, including the upload body when needed.
3. A successful response can carry the next nonce. Pub remembers it for that
   registration and passes it to the helper for the next proof. This avoids a
   preliminary challenge round trip for each package or HTTP request.

RFC 9449 defines this challenge on the protected request. It defines no
general-purpose endpoint where pub could fetch a resource-server nonce ahead
of time. The helper handles challenges from its own token-issuing endpoint
during acquisition. Pub uses resource-server nonces only within the issuing
repository's scope. Both the helper and server must support overlapping
requests, including a server choosing to accept a nonce for multiple fresh
proofs. An ordinary credential rejection invalidates the cached token and
preserves the user's registration. [DPoP specification, sections 8–9](https://www.rfc-editor.org/rfc/rfc9449.html#section-8)

### pub.dev compatibility

Private-repository challenges are exchanged with that repository. Pub.dev's
existing login, public downloads and publishing continue through their current
flows. Pub.dev would need server-side changes only if it chose to issue and
validate DPoP credentials for its own users.
