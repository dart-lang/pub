// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  forBothPubGetAndUpgrade((command) {
    test(
        'fails gracefully if the package server responds with broken package listings',
        () async {
      await servePackages((b) => b..serve('foo', '1.2.3'));
      globalPackageServer!.extraHandlers[RegExp('/api/packages/.*')] =
          expectAsync1((request) {
        expect(request.method, 'GET');
        return Response(200,
            body: jsonEncode({
              'notTheRight': {'response': 'type'}
            }));
      });
      await d.appDir({'foo': '1.2.3'}).create();

      await pubCommand(command,
          error: allOf([
            contains(
                'Got badly formatted response trying to find package foo at http://localhost:'),
            contains('), version solving failed.')
          ]),
          exitCode: exit_codes.DATA);
    });
  });
}
