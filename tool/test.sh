#!/bin/bash -e

### Test wrapper script.
# Many of the integration tests runs the `pub` command, this is slow if every
# invocation requires the dart compiler to load all the sources. This script
# will create a `bin/pub.dart.snapshot.dart2` which the tests can utilize.
# After creating the snapshot this script will forward arguments to
# `pub run test`, and ensure that the snapshot is deleted after tests have been
# run.
#
# Notice that it is critical that this file is deleted before running tests
# again, as tests otherwise won't load the pub sources.

# Find folder containing this script.
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT="$DIR/.."

# Always remove the snapshot
function cleanup {
  rm -f "$ROOT/bin/pub.dart.snapshot.dart2"
}
trap cleanup EXIT;

# Build a snapshot for faster testing
echo 'Building snapshot'
(
  cd "$ROOT/";
  rm -f "$ROOT/bin/pub.dart.snapshot.dart2"
  dart --snapshot=bin/pub.dart.snapshot.dart2 bin/pub.dart
)

# Run tests
echo 'Running tests'
pub run test "$@"
