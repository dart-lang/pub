// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:pub/src/tokens.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('check for auth header for hosted server', () async {
    await servePackages((builder) {
      builder.serve('foo', '1.0.0');
    });

    // get test hosted server and add token for it
    var hostedServer = globalPackageServer.url;
    await d
        .tokensFile([TokenEntry(server: hostedServer, token: 'ABC')]).create();

    await d.appDir({'foo': '1.0.0'}).create();

    await pubCommand(RunCommand.get,
        silent: allOf(
            [contains('${HttpHeaders.authorizationHeader}: Bearer ABC')]));
  });

  test('check for auth header through env var for hosted server', () async {
    await servePackages((builder) {
      builder.serve('foo', '1.0.0');
    });

    // get test hosted server and add token for it
    // use an env var that is always available HOME
    var hostedServer = globalPackageServer.url;
    await d.tokensFile(
        [TokenEntry(server: hostedServer, token: '\$HOME')]).create();

    await d.appDir({'foo': '1.0.0'}).create();

    await pubCommand(RunCommand.get,
        silent: allOf([
          contains(
              '${HttpHeaders.authorizationHeader}: Bearer ${Platform.environment['HOME']}')
        ]));
  });
}
