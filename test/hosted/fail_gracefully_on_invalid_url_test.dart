// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  forBothPubGetAndUpgrade((command) {
    test('fails gracefully if the url is invalid', () async {
      await d.dir(appPath, [
        d.appPubspec(
          dependencies: {
            'foo': {
              'hosted': {'name': 'foo', 'url': 'not@url-com'}
            }
          },
        )
      ]).create();

      await pubCommand(
        command,
        error: contains('url scheme must be https:// or http://'),
        exitCode: exit_codes.DATA,
        environment: {
          'PUB_MAX_HTTP_RETRIES': '2',
        },
      );
    });
    test('fails gracefully if the url has querystring', () async {
      await d.dir(appPath, [
        d.appPubspec(
          dependencies: {
            'foo': {
              'hosted': {'name': 'foo', 'url': 'http://example.foo/?key=value'}
            }
          },
        )
      ]).create();

      await pubCommand(
        command,
        error: contains('querystring'),
        exitCode: exit_codes.DATA,
        environment: {
          'PUB_MAX_HTTP_RETRIES': '2',
        },
      );
    });

    test('fails gracefully if the url has fragment', () async {
      await d.dir(appPath, [
        d.appPubspec(
          dependencies: {
            'foo': {
              'hosted': {'name': 'foo', 'url': 'http://example.foo/#hash'}
            }
          },
        )
      ]).create();

      await pubCommand(
        command,
        error: contains('fragment'),
        exitCode: exit_codes.DATA,
        environment: {
          'PUB_MAX_HTTP_RETRIES': '2',
        },
      );
    });

    test('fails gracefully if the url has user-info (1)', () async {
      await d.dir(appPath, [
        d.appPubspec(
          dependencies: {
            'foo': {
              'hosted': {'name': 'foo', 'url': 'http://user:pwd@example.foo/'}
            }
          },
        )
      ]).create();

      await pubCommand(
        command,
        error: contains('user-info'),
        exitCode: exit_codes.DATA,
        environment: {
          'PUB_MAX_HTTP_RETRIES': '2',
        },
      );
    });

    test('fails gracefully if the url has user-info (2)', () async {
      await d.dir(appPath, [
        d.appPubspec(
          dependencies: {
            'foo': {
              'hosted': {'name': 'foo', 'url': 'http://user@example.foo/'}
            }
          },
        )
      ]).create();

      await pubCommand(
        command,
        error: contains('user-info'),
        exitCode: exit_codes.DATA,
        environment: {
          'PUB_MAX_HTTP_RETRIES': '2',
        },
      );
    });
  });
}
