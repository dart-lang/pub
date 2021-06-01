// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart=2.10

import 'package:test/test.dart';
import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('with correct server url creates tokens.json that contains token',
      () async {
    await d.dir(cachePath).create();
    await runPub(
      args: [
        'login',
        '--server',
        'http://server.demo',
        '--token',
        'auth-token',
      ],
      output: contains(
          'You are now logged in to http://server.demo using bearer token.'),
    );

    await d.tokensFile({
      'version': '1.0',
      'hosted': [
        {
          'url': 'http://server.demo/',
          'credential': {'kind': 'Bearer', 'token': 'auth-token'},
        }
      ]
    }).validate();
  });

  test('with invalid server url returns error', () async {
    await d.dir(cachePath).create();
    await runPub(
      args: [
        'login',
        '--server',
        'http:;://invalid-url,.com',
        '--token',
        'auth-token',
      ],
      error: contains('Invalid or malformed server URL provided.'),
      exitCode: exit_codes.USAGE,
    );

    await d.dir(cachePath, [d.nothing('tokens.json')]).validate();
  });

  test('without token returns error', () async {
    await d.dir(cachePath).create();
    await runPub(
      args: [
        'login',
        '--server',
        'http://server.demo',
      ],
      error: contains('Must specify a token.'),
      exitCode: exit_codes.USAGE,
    );

    await d.dir(cachePath, [d.nothing('tokens.json')]).validate();
  });
}
