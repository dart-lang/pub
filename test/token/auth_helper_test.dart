// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:pub/src/path.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test(
    'publish helper receives exact archive identity and stays in scope',
    () async {
      final server = await servePackages();
      const path = '/org/Engineering/feeds/internal';
      final repository = '${server.url}$path/';
      await d.validPackage(pubspecExtras: {'publish_to': repository}).create();
      await runPub(
        args: ['lish', '--to-archive', p.join('..', 'release.tar.gz')],
      );
      await d.file('helper.dart', r"""
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  File(args.single).writeAsStringSync(await utf8.decoder.bind(stdin).join(),
      mode: FileMode.append);
  stdout.write(jsonEncode({
    'token': 'access-token',
    'expiresAt': DateTime.now().toUtc().add(const Duration(hours: 1)).toIso8601String(),
  }));
}
""").create();
      final command = [
        Platform.resolvedExecutable,
        d.path('helper.dart'),
        d.path('calls'),
      ];
      final registration = d.tokensFile({
        'version': 1,
        'hosted': [
          {'url': repository, 'authHelper': command},
        ],
      });
      await registration.create();
      final pub = await startPublish(
        server,
        overrideDefaultHostedServer: false,
        args: ['--from-archive', d.path('release.tar.gz')],
      );
      await confirmPublish(pub);
      server.expect('GET', '$path/api/packages/versions/new', (request) {
        expect(request.headers['authorization'], 'Bearer access-token');
        return Response.found(
          Uri.parse(repository).resolve('/org/engineering/feeds/internal/form'),
        );
      });
      server.expect('GET', '/org/engineering/feeds/internal/form', (request) {
        expect(request.headers['authorization'], isNull);
        return Response.ok(
          jsonEncode({
            'url': '${server.url}/upload',
            'fields': <String, String>{},
          }),
        );
      });
      server.expect('POST', '/upload', (request) async {
        expect(request.headers['authorization'], isNull);
        await request.read().drain<void>();
        return Response.found(Uri.parse(repository).resolve('complete'));
      });
      server.expect('GET', '$path/complete', (request) {
        expect(request.headers['authorization'], 'Bearer access-token');
        return Response(401);
      });
      await pub.shouldExit(65);
      await registration.validate();
      expect(jsonDecode(File(d.path('calls')).readAsStringSync()), {
        'protocolVersion': 1,
        'action': 'acquire',
        'repository': repository,
        'interactive': false,
        'operation': 'publish',
        'package': 'test_pkg',
        'version': '1.0.0',
        'archiveSha256':
            sha256
                .convert(File(d.path('release.tar.gz')).readAsBytesSync())
                .toString(),
      });
    },
  );
}
