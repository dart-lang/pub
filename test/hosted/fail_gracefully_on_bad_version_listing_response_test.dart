// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../golden_file.dart';
import '../test_pub.dart';

void main() {
  forBothPubGetAndUpgrade((command) {
    test(
        'fails gracefully if the package server responds with broken package listings',
        () async {
      final server = await servePackages();
      server.serve('foo', '1.2.3');
      server.expect(
        'GET',
        RegExp('/api/packages/.*'),
        expectAsync1((request) {
          return Response(
            200,
            body: jsonEncode({
              'notTheRight': {'response': 'type'}
            }),
          );
        }),
      );
      await d.appDir(dependencies: {'foo': '1.2.3'}).create();

      await pubCommand(
        command,
        error: allOf([
          contains(
            'Got badly formatted response trying to find package foo at http://localhost:',
          ),
          contains('), version solving failed.')
        ]),
        exitCode: exit_codes.DATA,
      );
    });
  });

  testWithGolden('bad_json', (ctx) async {
    final server = await servePackages();
    server.serve('foo', '1.2.3');
    server.expect('GET', RegExp('/api/packages/.*'), (request) {
      return Response(
        200,
        body: jsonEncode({
          'notTheRight': {'response': 'type'}
        }),
      );
    });
    await d.appDir(dependencies: {'foo': '1.2.3'}).create();

    await ctx.run(['get']);
  });

  testWithGolden('403', (ctx) async {
    final server = await servePackages();
    server.serve('foo', '1.2.3');
    server.expect('GET', RegExp('/api/packages/.*'), (request) {
      return Response(
        403,
        body: jsonEncode({
          'notTheRight': {'response': 'type'}
        }),
      );
    });
    await d.appDir(dependencies: {'foo': '1.2.3'}).create();

    await ctx.run(['get']);
  });

  testWithGolden('401', (ctx) async {
    final server = await servePackages();
    server.serve('foo', '1.2.3');
    server.expect('GET', RegExp('/api/packages/.*'), (request) {
      return Response(
        401,
        body: jsonEncode({
          'notTheRight': {'response': 'type'}
        }),
      );
    });
    await d.appDir(dependencies: {'foo': '1.2.3'}).create();

    await ctx.run(['get']);
  });

  testWithGolden('403-with-message', (ctx) async {
    final server = await servePackages();
    server.serve('foo', '1.2.3');
    server.expect('GET', RegExp('/api/packages/.*'), (request) {
      return Response(
        403,
        headers: {
          'www-authenticate': 'Bearer realm="pub", message="<message>"',
        },
        body: jsonEncode({
          'notTheRight': {'response': 'type'}
        }),
      );
    });
    await d.appDir(dependencies: {'foo': '1.2.3'}).create();

    await ctx.run(['get']);
  });

  testWithGolden('401-with-message', (ctx) async {
    final server = await servePackages();
    server.serve('foo', '1.2.3');
    server.expect('GET', RegExp('/api/packages/.*'), (request) {
      return Response(
        401,
        headers: {
          'www-authenticate': 'Bearer realm="pub", message="<message>"',
        },
        body: jsonEncode({
          'notTheRight': {'response': 'type'}
        }),
      );
    });
    await d.appDir(dependencies: {'foo': '1.2.3'}).create();

    await ctx.run(['get']);
  });
}
