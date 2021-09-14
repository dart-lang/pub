// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart=2.10

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('with one matching token, removes it', () async {
    await d.tokensFile({
      'version': 1,
      'hosted': [
        {'url': 'https://server.demo', 'token': 'auth-token'}
      ]
    }).create();

    await runPub(args: ['token', 'remove', 'https://server.demo']);

    await d.tokensFile({'version': 1, 'hosted': []}).validate();
  });

  test('without any matching schemes, does nothing', () async {
    await d.tokensFile({
      'version': 1,
      'hosted': [
        {'url': 'https://server.demo', 'token': 'auth-token'}
      ]
    }).create();

    await runPub(
      args: ['token', 'remove', 'https://another-server.demo'],
      error:
          'No secret token for package repository "https://another-server.demo"'
          ' was found.',
      exitCode: exit_codes.DATA,
    );

    await d.tokensFile({
      'version': 1,
      'hosted': [
        {'url': 'https://server.demo', 'token': 'auth-token'}
      ]
    }).validate();
  });

  test('removes all tokens', () async {
    await d.tokensFile({
      'version': 1,
      'hosted': [
        {'url': 'https://server.dev', 'token': 'auth-token'},
        {'url': 'https://server2.com', 'token': 'auth-token'}
      ]
    }).create();

    await runPub(args: ['token', 'remove', '--all']);

    await d.dir(cachePath, [d.nothing('tokens.json')]).validate();
  });
}
