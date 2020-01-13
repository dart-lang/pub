#!/bin/bash -e

### Test wrapper script.
# Many of the integration tests runs the `pub` command, this is slow if every
# invocation requires the dart compiler to load all the sources. This script
# will create a `pub.XXX.dart.snapshot.dart2` which the tests can utilize.
# After creating the snapshot this script will forward arguments to
# `pub run test`, and ensure that the snapshot is deleted after tests have been
# run.

# Find folder containing this script.
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT="$DIR/.."

# PATH to a snapshot file.
PUB_SNAPSHOT_FILE=`tempfile -p 'pub.' -s '.dart.snapshot.dart2'`;

# Always remove the snapshot
function cleanup {
  rm -f "$PUB_SNAPSHOT_FILE";
}
trap cleanup EXIT;

# Build a snapshot for faster testing
echo 'Building snapshot'
(
  cd "$ROOT/";
  rm -f "$PUB_SNAPSHOT_FILE"
  dart --snapshot="$PUB_SNAPSHOT_FILE" bin/pub.dart
)

# Run tests
echo 'Running tests'
export _PUB_TEST_SNAPSHOT="$PUB_SNAPSHOT_FILE"
pub run test -r expanded "$@"
