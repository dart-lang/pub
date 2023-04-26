// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

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

  group('with environment variable creates tokens.json that contains env var',
      () {
    test('without environment variable provided', () async {
      await d.tokensFile({
        'version': 1,
        'hosted': [
          {'url': 'https://example.com', 'token': 'abc'},
        ]
      }).create();

      await runPub(
        args: ['token', 'add', 'https://example.com/', '--env-var', 'TOKEN'],
        error: 'Environment variable "TOKEN" is not defined.',
      );

      await d.tokensFile({
        'version': 1,
        'hosted': [
          {'url': 'https://example.com', 'env': 'TOKEN'},
        ]
      }).validate();
    });

    test('with environment variable provided', () async {
      await d.tokensFile({
        'version': 1,
        'hosted': [
          {'url': 'https://example.com', 'token': 'abc'},
        ]
      }).create();

      await runPub(
        args: ['token', 'add', 'https://example.com/', '--env-var', 'TOKEN'],
        environment: {'TOKEN': 'secret'},
        error: isNot(contains('is not defined.')),
      );

      await d.tokensFile({
        'version': 1,
        'hosted': [
          {'url': 'https://example.com', 'env': 'TOKEN'},
        ]
      }).validate();
    });
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
    await configDir([]).create();
    await runPub(
      args: ['token', 'add', 'http:;://invalid-url,.com'],
      error: contains('Invalid [hosted-url]'),
      exitCode: exit_codes.USAGE,
    );

    await configDir([d.nothing('pub-tokens.json')]).validate();
  });

  test('with invalid token returns error', () async {
    await configDir([]).create();

    await runPub(
      args: ['token', 'add', 'https://pub.dev'],
      error: contains('The entered token is not a valid Bearer token.'),
      input: ['auth-token@'], // '@' is not allowed in bearer tokens
      exitCode: exit_codes.DATA,
    );

    await configDir([d.nothing('pub-tokens.json')]).validate();
  });

  test('with non-secure server url returns error', () async {
    await configDir([]).create();
    await runPub(
      args: ['token', 'add', 'http://mypub.com'],
      error: contains('insecure repositories cannot use authentication'),
      exitCode: exit_codes.USAGE,
    );

    await configDir([d.nothing('pub-tokens.json')]).validate();
  });

  test(
      'with non-secure localhost url creates pub-tokens.json that contains token',
      () async {
    await d.dir(configPath).create();

    await runPub(
      args: ['token', 'add', 'http://localhost/'],
      input: ['auth-token'],
    );

    await d.tokensFile({
      'version': 1,
      'hosted': [
        {'url': 'http://localhost', 'token': 'auth-token'}
      ]
    }).validate();
  });

  test('with empty environment gives error message', () async {
    await runPub(
      args: ['token', 'add', 'https://mypub.com'],
      input: ['auth-token'],
      error: contains('No config dir found.'),
      exitCode: exit_codes.DATA,
      environment: {'_PUB_TEST_CONFIG_DIR': null},
      includeParentHomeAndPath: false,
    );
  });

  test('with https://pub.dartlang.org rewrites to https://pub.dev', () async {
    await runPub(
      args: ['token', 'add', 'https://pub.dartlang.org'],
      input: ['auth-token'],
      silent: contains(
        'Using https://pub.dev instead of https://pub.dartlang.org.',
      ),
    );

    await d.tokensFile({
      'version': 1,
      'hosted': [
        {'url': 'https://pub.dev', 'token': 'auth-token'}
      ]
    }).validate();
  });
}
