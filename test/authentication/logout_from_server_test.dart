// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart=2.10

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('with one matching scheme, removes the entry.', () async {
    await d.tokensFile({
      'version': '1.0',
      'hosted': [
        {
          'url': 'http://server.demo/',
          'credential': {'kind': 'Bearer', 'token': 'auth-token'},
        }
      ]
    }).create();

    await runPub(
      args: ['logout', '--server', 'http://server.demo'],
      output: contains('Logging out of http://server.demo/.'),
    );

    await d.tokensFile({'version': '1.0', 'hosted': []}).validate();
  });

  test('with multiple matching schemes, removes all matching entries.',
      () async {
    await d.tokensFile({
      'version': '1.0',
      'hosted': [
        {
          'url': 'http://server.demo/',
          'credential': {'kind': 'Bearer', 'token': 'auth-token'},
        },
        {
          'url': 'http://server.demo/sub',
          'credential': {'kind': 'Bearer', 'token': 'auth-token'},
        },
        {
          'url': 'http://another-.demo/',
          'credential': {'kind': 'Bearer', 'token': 'auth-token'},
        }
      ]
    }).create();

    await runPub(
      args: ['logout', '--server', 'http://server.demo/sub'],
      output: allOf(
        contains('Logging out of http://server.demo/.'),
        contains('Logging out of http://server.demo/sub/.'),
      ),
    );

    await d.tokensFile({
      'version': '1.0',
      'hosted': [
        {
          'url': 'http://another-.demo/',
          'credential': {'kind': 'Bearer', 'token': 'auth-token'},
        }
      ]
    }).validate();
  });

  test('without an matching schemes, does nothing.', () async {
    await d.tokensFile({
      'version': '1.0',
      'hosted': [
        {
          'url': 'http://server.demo/',
          'credential': {'kind': 'Bearer', 'token': 'auth-token'},
        }
      ]
    }).create();

    await runPub(
      args: ['logout', '--server', 'http://another-server.demo'],
      output: 'No matching credential found for http://another-server.demo. '
          'Cannot log out.',
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
}
