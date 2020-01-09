// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../../test_pub.dart';

void main() {
  test('fails if the version constraint cannot be parsed', () {
    return runPub(args: ['cache', 'add', 'foo', '-v', '1.0'], error: '''
            Could not parse version "1.0". Unknown text at "1.0".
            
            Usage: pub cache add <package> [--version <constraint>] [--all]
            -h, --help       Print this usage information.
                --all        Install all matching versions.
            -v, --version    Version constraint.

            Run "pub help" to see global options.
            See https://dart.dev/tools/pub/cmd/pub-cache for detailed documentation.
            ''', exitCode: exit_codes.USAGE);
  });
}
