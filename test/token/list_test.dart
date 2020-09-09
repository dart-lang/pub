// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/tokens.dart';
import 'package:test/test.dart';
import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('lists nothing when no tokens are set', () async {
    await runPub(args: ['token', 'list'], output: '\n');
  });

  test('lists added tokens', () async {
    await d.tokensFile(
        [TokenEntry(server: 'https://server.com', token: 'token1')]).create();
    await runPub(args: ['token', 'list'], output: '''
https://server.com -> token1
''');
  });

  test('lists added tokens with different length and sorted', () async {
    await d.tokensFile([
      TokenEntry(server: 'https://server.com', token: 'token1'),
      TokenEntry(server: 'https://longer-server.com', token: 'token2')
    ]).create();
    await runPub(args: ['token', 'list'], output: '''
https://longer-server.com -> token2
https://server.com        -> token1
''');
  });

  test('with a malformed tokens.json', () async {
    await d.dir(cachePath, [d.file('tokens.json', '{bad json')]).create();

    var pub = await startPub(
      args: ['token', 'list'],
    );

    await pub.shouldExit(1);
  });
}
