// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart=2.10

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('with correct server url creates tokens.json that contains token',
      () async {
    await d.dir(cachePath).create();
    await runPub(
      args: ['token', 'add', 'https://server.demo/'],
      input: ['auth-token'],
    );

    await d.tokensFile({
      'version': 1,
      'hosted': [
        {'url': 'https://server.demo', 'token': 'auth-token'}
      ]
    }).validate();
  });

  test('with invalid server url returns error', () async {
    await d.dir(cachePath).create();
    await runPub(
      args: ['token', 'add', 'http:;://invalid-url,.com'],
      error: contains('Invalid [hosted-url]'),
      exitCode: exit_codes.USAGE,
    );

    await d.dir(cachePath, [d.nothing('tokens.json')]).validate();
  });

  test('with non-secure server url returns error', () async {
    await d.dir(cachePath).create();
    await runPub(
      args: ['token', 'add', 'http://mypub.com'],
      error: contains('Unsecure package repository could not be added.'),
      exitCode: exit_codes.DATA,
    );

    await d.dir(cachePath, [d.nothing('tokens.json')]).validate();
  });
}
