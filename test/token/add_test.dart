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
    return runPub(args: ['token', 'add'], error: '''
Must specify both server and token.

Usage: pub token add --server <url> --token <value>
-h, --help      Print this usage information.
-s, --server    Url for the server.
-t, --token     Token. Environment variable can be used with \'\$YOUR_VAR\'.

Run "pub help" to see global options.
''', exitCode: exit_codes.USAGE);
  });

  test('fails when server url has no scheme', () async {
    return runPub(
        args: ['token', 'add', '-s', 'www.error.com', '-t', 'XYZ'], error: '''
`server` must include a scheme such as "https://".
www.error.com is invalid.

Usage: pub token add --server <url> --token <value>
-h, --help      Print this usage information.
-s, --server    Url for the server.
-t, --token     Token. Environment variable can be used with \'\$YOUR_VAR\'.

Run "pub help" to see global options.
''', exitCode: exit_codes.USAGE);
  });

  test('fails when server url has no empty path', () async {
    return runPub(args: [
      'token',
      'add',
      '-s',
      'https://www.error.com/something',
      '-t',
      'XYZ'
    ], error: '''
`server` must not have a path defined.
https://www.error.com/something is invalid.

Usage: pub token add --server <url> --token <value>
-h, --help      Print this usage information.
-s, --server    Url for the server.
-t, --token     Token. Environment variable can be used with \'\$YOUR_VAR\'.

Run "pub help" to see global options.
''', exitCode: exit_codes.USAGE);
  });

  test('fails when server url has query', () async {
    return runPub(
        args: ['token', 'add', '-s', 'https://www.error.com?x=y', '-t', 'XYZ'],
        error: '''
`server` must not have a query string defined.
https://www.error.com?x=y is invalid.

Usage: pub token add --server <url> --token <value>
-h, --help      Print this usage information.
-s, --server    Url for the server.
-t, --token     Token. Environment variable can be used with \'\$YOUR_VAR\'.

Run "pub help" to see global options.
''',
        exitCode: exit_codes.USAGE);
  });

  test('add token when no tokens.json exists', () async {
    await runPub(
        args: ['token', 'add', '-s', 'https://www.mypub.com', '-t', 'XYZ'],
        output: '''
Token for https://www.mypub.com added
''');

    await d.tokensFile(
        [TokenEntry(server: 'https://www.mypub.com', token: 'XYZ')]).validate();
  });
}
