// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/tokens.dart';
import 'package:test/test.dart';
import 'package:pub/src/exit_codes.dart' as exit_codes;
import '../descriptor.dart' as d;

import '../test_pub.dart';

void main() {
  test('fails if no parameters are given', () async {
    return runPub(args: ['token', 'remove'], error: '''
Must specify a server.

Usage: pub token remove [--server <url>] [--all]
-h, --help      Print this usage information.
-s, --server    Url for the server.
-a, --all       Remove all stored tokens.

Run "pub help" to see global options.
''', exitCode: exit_codes.USAGE);
  });

  test('fails when server url has no scheme', () async {
    return runPub(args: ['token', 'remove', '-s', 'www.error.com'], error: '''
`server` must include a scheme such as "https://".
www.error.com is invalid.

Usage: pub token remove [--server <url>] [--all]
-h, --help      Print this usage information.
-s, --server    Url for the server.
-a, --all       Remove all stored tokens.

Run "pub help" to see global options.
''', exitCode: exit_codes.USAGE);
  });

  test('fails when server url has no empty path', () async {
    return runPub(args: ['token', 'remove', '-s', 'https://www.error.com/something'], error: '''
`server` must not have a path defined.
https://www.error.com/something is invalid.

Usage: pub token remove [--server <url>] [--all]
-h, --help      Print this usage information.
-s, --server    Url for the server.
-a, --all       Remove all stored tokens.

Run "pub help" to see global options.
''', exitCode: exit_codes.USAGE);
  });

  test('fails when server url has query', () async {
    return runPub(args: ['token', 'remove', '-s', 'https://www.error.com?x=y'], error: '''
`server` must not have a query string defined.
https://www.error.com?x=y is invalid.

Usage: pub token remove [--server <url>] [--all]
-h, --help      Print this usage information.
-s, --server    Url for the server.
-a, --all       Remove all stored tokens.

Run "pub help" to see global options.
''', exitCode: exit_codes.USAGE);
  });

  test('remove token when server is not in tokens.json', () async {
    await runPub(args: ['token', 'remove', '-s', 'https://www.mypub.com'], output: '''
https://www.mypub.com not found in tokens.json
''');
  });

  test('remove token that is present in token.json', () async {
    await d.tokensFile([TokenEntry(server: 'https://www.mypub.com', token: 'ABC')]).create();

    await runPub(args: ['token', 'remove', '-s', 'https://www.mypub.com'], output: '''
Token for https://www.mypub.com removed
''');

    await d.tokensFile([]).validate();
  });

  test('remove all tokens present in token.json', () async {
    await d.tokensFile([TokenEntry(server: 'https://www.mypub.com', token: 'ABC')]).create();

    await runPub(args: ['token', 'remove', '-a'], output: 'All entries deleted');
  });
}
