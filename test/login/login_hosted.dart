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
    return runPub(args: ['login'], error: '''
Must specify a server to log in.

Usage: pub login <server>
-h, --help    Print this usage information.

Run "pub help" to see global options.
''', exitCode: exit_codes.USAGE);
  });

  test('fails when server url has no scheme', () async {
    return runPub(args: ['login', 'www.error.com'], error: '''
`server` must include a scheme such as "https://".
www.error.com is invalid.

Usage: pub login <server>
-h, --help    Print this usage information.

Run "pub help" to see global options.
''', exitCode: exit_codes.USAGE);
  });

  test('fails when server url has no empty path', () async {
    return runPub(args: ['login', 'https://www.error.com/something'], error: '''
`server` must not have a path defined.
https://www.error.com/something is invalid.

Usage: pub login <server>
-h, --help    Print this usage information.

Run "pub help" to see global options.
''', exitCode: exit_codes.USAGE);
  });

  test('fails when server url has query', () async {
    return runPub(args: ['login', 'https://www.error.com?x=y'], error: '''
`server` must not have a query string defined.
https://www.error.com?x=y is invalid.

Usage: pub login <server>
-h, --help    Print this usage information.

Run "pub help" to see global options.
''', exitCode: exit_codes.USAGE);
  });

  test('fails when server is official server', () async {
    return runPub(args: ['login', 'https://pub.dev'], error: '''
`server` cannot be the official package server.
https://pub.dev is invalid.

Usage: pub login <server>
-h, --help    Print this usage information.

Run "pub help" to see global options.
''', exitCode: exit_codes.USAGE);
  });

  test('prompt for token that is new', () async {
    var pub = await startLogin('https://www.mypub.com');
    pub.stdin.writeln('XYZ');
    await expectLater(
        pub.stdout,
        emitsInOrder([
          'Enter a token value: ',
          'Token for https://www.mypub.com added'
        ]));
    await d.tokensFile(
        [TokenEntry(server: 'https://www.mypub.com', token: 'XYZ')]).validate();
  });

  test('prompt for token that is already in secrets.json', () async {
    await d.tokensFile(
        [TokenEntry(server: 'https://www.mypub.com', token: 'ABC')]).create();

    var pub = await startLogin('https://www.mypub.com');
    pub.stdin.writeln('XYZ');
    await expectLater(
        pub.stdout,
        emitsInOrder([
          'Enter a token value: ',
          'Token for https://www.mypub.com updated'
        ]));
    await d.tokensFile(
        [TokenEntry(server: 'https://www.mypub.com', token: 'XYZ')]).validate();
  });
}
