# Hosted repository authentication helpers (draft protocol)

A user registers a trusted executable for a canonical hosted repository URL:

    dart pub token add https://packages.example/org/team/feed/ --auth-helper=/opt/bin/onepub --auth-helper-arg=_pub-auth

The option takes an absolute executable path. On Windows use a native .exe.
Each repeated argument is one literal argument. Pub stores the command in the
user's pub-tokens.json and starts it directly in its installation directory.
Use fixed arguments only for nonsecret configuration. Packages and servers
cannot register helpers. Registration, listing and removal do not execute them.

Repository selection uses the complete hosted URL (scheme, host, port and
case-sensitive path). The repository defines the path hierarchy. A registration
for a parent is not inherited by a nested repository in a pubspec. Within an
operation pub sends credentials only to endpoints under the selected base path
on the same origin. A repository should place protected endpoints beneath its
base; archive and upload URLs outside it must function without this credential.
The repository must independently enforce the credential's audience and rights.

## Protocol version 1

The helper reads one UTF-8 JSON object from stdin through EOF and returns one
UTF-8 JSON object on stdout with exit status zero. Calls are noninteractive.
Pub discards stderr, limits stdout to 64 KiB and allows 30 seconds for a
running helper. Nonzero exit, malformed output and expired credentials fail
the operation without printing helper output.

Every input includes protocolVersion (1), repository (canonical URL), action
and interactive (false). An acquire request includes operation (read or
publish) and the package when known. A publish request also carries the
manifest version and archiveSha256, the lowercase hex SHA-256 of the exact
compressed upload bytes. The context describes intent; the server verifies
permission, the manifest and the digest.

    {"protocolVersion":1,"action":"acquire","repository":"https://packages.example/org/team/feed/","interactive":false,"operation":"read","package":"widgets"}

    {"token":"example","expiresAt":"2030-01-01T12:00:00Z","tokenType":"Bearer"}

expiresAt is a UTC timestamp. Pub coalesces concurrent acquisitions for the same
registration and operation context, and reuses unexpired grants in memory.
An authenticated 401 invalidates the cached grant and keeps the registration.
Pub does not replay the failed operation to recover authentication.

For a sender-constrained grant return tokenType DPoP. For each authenticated
request pub then invokes the helper with action prove, token, method and uri
(the absolute target without query or fragment). Return a JSON object with a
proof string containing a compact signed JWT. The helper constructs a fresh
[RFC 9449](https://www.rfc-editor.org/rfc/rfc9449.html) proof including the
access-token hash. This draft supports servers operating without DPoP nonces.
Cross-scope transfers carry no repository proof or credential. A server that
requires sender binding through archive redemption must keep the redemption
endpoint in scope. This proof method and the acquire fields are proposed for
maintainer review. Existing pub.dev authentication requires no service change.
