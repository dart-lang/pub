// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/tokens.dart';
import 'package:test/test.dart';
import '../descriptor.dart' as d;

import '../test_pub.dart';

void main() {
  test('log out of not logged in server', () async {
    await runPub(args: ['logout', 'https://www.mypub.com'], output: '''
No token found for https://www.mypub.com.
''');
  });

  test('log out for logged in server', () async {
    await d.tokensFile(
        [TokenEntry(server: 'https://www.mypub.com/', token: 'ABC')]).create();

    await runPub(args: ['logout', 'https://www.mypub.com'], output: '''
Log out https://www.mypub.com successful.
''');

    await d.tokensFile([]).validate();
  });

  test('log out for all servers', () async {
    await d.dir(cachePath, [d.nothing('credentials.json')]).create();
    await d.tokensFile([
      TokenEntry(server: 'https://www.server1.com/', token: 'ABC'),
    ]).create();

    await runPub(
        args: ['logout', '--all'],
        output: contains('Log out https://www.server1.com/ successful.'));
  });
}
