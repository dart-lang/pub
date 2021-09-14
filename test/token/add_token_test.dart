// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart=2.10

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('with correct server url creates pub-tokens.json that contains token',
      () async {
    await d.tokensFile({
      'version': 1,
      'hosted': [
        {'url': 'https://example.com', 'token': 'abc'},
      ]
    }).create();

    await runPub(
      args: ['token', 'add', 'https://server.demo/'],
      input: ['auth-token'],
    );

    await d.tokensFile({
      'version': 1,
      'hosted': [
        {'url': 'https://example.com', 'token': 'abc'},
        {'url': 'https://server.demo', 'token': 'auth-token'}
      ]
    }).validate();
  });

  test('persists unknown fields on unmodified entries', () async {
    await d.tokensFile({
      'version': 1,
      'hosted': [
        {
          'url': 'https://example.com',
          'unknownField': '123',
          'nestedField': [
            {
              'username': 'user',
              'password': 'pass',
            },
          ],
        }
      ]
    }).create();

    await runPub(
      args: ['token', 'add', 'https://server.demo/'],
      input: ['auth-token'],
    );

    await d.tokensFile({
      'version': 1,
      'hosted': [
        {
          'url': 'https://example.com',
          'unknownField': '123',
          'nestedField': [
            {
              'username': 'user',
              'password': 'pass',
            },
          ],
        },
        {'url': 'https://server.demo', 'token': 'auth-token'}
      ]
    }).validate();
  });

  test('with invalid server url returns error', () async {
    await d.dir(configPath).create();
    await runPub(
      args: ['token', 'add', 'http:;://invalid-url,.com'],
      error: contains('Invalid [hosted-url]'),
      exitCode: exit_codes.USAGE,
    );

    await d.dir(configPath, [d.nothing('pub-tokens.json')]).validate();
  });

  test('with non-secure server url returns error', () async {
    await d.dir(configPath).create();
    await runPub(
      args: ['token', 'add', 'http://mypub.com'],
      error: contains('Unsecure package repository could not be added.'),
      exitCode: exit_codes.DATA,
    );

    await d.dir(configPath, [d.nothing('pub-tokens.json')]).validate();
  });
}
