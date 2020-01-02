// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_test_handler/shelf_test_handler.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  forBothPubGetAndUpgrade((command) {
    test('sends the correct Accept header', () async {
      var server = await ShelfTestServer.create();

      await d.appDir({
        'foo': {
          'hosted': {'name': 'foo', 'url': server.url.toString()}
        }
      }).create();

      var pub = await startPub(args: [command.name]);

      server.handler.expect('GET', '/api/packages/foo', (request) {
        expect(
            request.headers['accept'], equals('application/vnd.pub.v2+json'));
        return shelf.Response(200);
      });

      await pub.kill();
    });

    test('prints a friendly error if the version is out-of-date', () async {
      var server = await ShelfTestServer.create();

      await d.appDir({
        'foo': {
          'hosted': {'name': 'foo', 'url': server.url.toString()}
        }
      }).create();

      var pub = await startPub(args: [command.name]);

      server.handler
          .expect('GET', '/api/packages/foo', (request) => shelf.Response(406));

      await pub.shouldExit(1);

      expect(
          pub.stderr,
          emitsLines(
              'Pub 0.1.2+3 is incompatible with the current version of localhost.\n'
              'Upgrade pub to the latest version and try again.'));
    });
  });
}
