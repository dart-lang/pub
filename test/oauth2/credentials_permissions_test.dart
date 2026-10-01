// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:io';

import 'package:pub/src/io.dart';
import 'package:pub/src/path.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

void main() {
  test(
    'saving credentials creates pub-credentials.json with mode 0600',
    () async {
      await d.validPackage().create();
      await servePackages();
      final pub = await startPublish(globalServer);
      await confirmPublish(pub);
      await authorizePub(pub, globalServer);

      globalServer.expect('GET', '/api/packages/versions/new', (request) {
        expect(
          request.headers,
          containsPair('authorization', 'Bearer access-token'),
        );
        return shelf.Response(200);
      });

      await pub.shouldExit(1);

      await d.credentialsFile(globalServer, 'access-token').validate();

      if (Platform.isLinux || Platform.isMacOS) {
        final credentialsPath = p.join(
          d.sandbox,
          configPath,
          'dart',
          'pub-credentials.json',
        );
        final dartDirPath = p.join(d.sandbox, configPath, 'dart');

        final fileMode = File(credentialsPath).statSync().mode & 0x1ff;
        expect(
          fileMode,
          equals(384), // 0600
          reason:
              'pub-credentials.json should have owner-only permissions (0600)',
        );

        final dirMode = Directory(dartDirPath).statSync().mode & 0x1ff;
        expect(
          dirMode,
          equals(448), // 0700
          reason: 'dart config dir should have owner-only permissions (0700)',
        );
      }
    },
  );

  test(
    'loading credentials tightens permissions on existing pub-credentials.json',
    () async {
      await d.validPackage().create();
      final server = await PackageServer.start();

      // Pre-create credentials file
      await d.credentialsFile(server, 'access-token').create();

      if (Platform.isLinux || Platform.isMacOS) {
        final credentialsPath = p.join(
          d.sandbox,
          configPath,
          'dart',
          'pub-credentials.json',
        );
        final dartDirPath = p.join(d.sandbox, configPath, 'dart');

        chmod(420, credentialsPath); // 0644
        chmod(493, dartDirPath); // 0755

        expect(File(credentialsPath).statSync().mode & 0x1ff, equals(420));
        expect(Directory(dartDirPath).statSync().mode & 0x1ff, equals(493));

        // Running publish with existing credentials will load them
        final pub = await startPublish(server);
        await confirmPublish(pub);

        server.expect('GET', '/api/packages/versions/new', (request) {
          return shelf.Response(200);
        });

        await pub.shouldExit(1);

        expect(
          File(credentialsPath).statSync().mode & 0x1ff,
          equals(384), // 0600
          reason: 'pub-credentials.json should be tightened to 0600',
        );
        expect(
          Directory(dartDirPath).statSync().mode & 0x1ff,
          equals(448), // 0700
          reason: 'dart config dir should be tightened to 0700',
        );
      }
    },
  );
}
