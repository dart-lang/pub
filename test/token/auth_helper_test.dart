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

Future<void> registerProofHelper(String repository) async {
  await d.file('proof.dart', r"""
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final input = jsonDecode(await utf8.decoder.bind(stdin).join());
  stdout.write(jsonEncode(input['action'] == 'prove'
      ? {'proof': 'header.' + (input['nonce'] ?? 'initial') + '.signature'}
      : {'tokenType': 'DPoP', 'token': 'token',
         'expiresAt': DateTime.now().toUtc().add(const Duration(hours: 1)).toIso8601String()}));
}
""").create();
  await d.tokensFile({
    'version': 1,
    'hosted': [
      {
        'url': repository,
        'authHelper': [Platform.resolvedExecutable, d.path('proof.dart')],
      },
    ],
  }).create();
}

Response challenge(String nonce) => Response(
  401,
  headers: {
    'www-authenticate': 'DPoP error="use_dpop_nonce"',
    'dpop-nonce': nonce,
  },
);

void main() {
  test(
    'read retries with a nonce and uses the next nonce for the download',
    () async {
      final server = await servePackages();
      server.serve('foo', '1.2.3');
      final repository = '${server.url}/feed/';
      await registerProofHelper(repository);
      await d
          .appDir(
            dependencies: {
              'foo': {'hosted': repository, 'version': '1.2.3'},
            },
          )
          .create();
      var attempts = 0;
      server.handle('/feed/api/packages/foo', (request) {
        if (++attempts == 1) {
          expect(request.headers['dpop'], 'header.initial.signature');
          return challenge('read1');
        }
        expect(request.headers['dpop'], 'header.read1.signature');
        return Response.ok(
          jsonEncode({
            'name': 'foo',
            'versions': [
              {
                'pubspec': {
                  'name': 'foo',
                  'version': '1.2.3',
                  'environment': {'sdk': '^3.0.0'},
                },
                'version': '1.2.3',
                'archive_url': '${repository}download',
              },
            ],
          }),
          headers: {'content-type': server.contentType, 'dpop-nonce': 'read2'},
        );
      });
      server.expect('GET', '/feed/download', (request) {
        expect(request.headers['dpop'], 'header.read2.signature');
        return Response.found(
          Uri.parse('${server.url}/packages/foo/versions/1.2.3.tar.gz'),
        );
      });
      await pubGet();
      expect(attempts, 2);
    },
  );

  test(
    'publish retries the challenged upload and bounds repeated challenges',
    () async {
      final server = await servePackages();
      await registerProofHelper(server.url);
      await d.validPackage().create();
      final pub = await startPublish(
        server,
        overrideDefaultHostedServer: false,
      );
      await confirmPublish(pub);
      server.expect('GET', '/api/packages/versions/new', (request) {
        return Response.ok(
          jsonEncode({
            'url': '${server.url}/upload',
            'fields': <String, String>{},
          }),
          headers: {
            'content-type': 'application/json',
            'dpop-nonce': 'upload1',
          },
        );
      });
      var uploads = 0;
      server.handle('/upload', (request) async {
        expect(request.method, 'POST');
        expect(
          await request.read().expand((bytes) => bytes).length,
          greaterThan(0),
        );
        expect(request.headers['dpop'], 'header.upload${++uploads}.signature');
        if (uploads == 1) return challenge('upload2');
        return Response.found(Uri.parse('${server.url}/complete'));
      });
      var completions = 0;
      server.handle('/complete', (request) {
        expect(
          request.headers['dpop'],
          completions == 0
              ? 'header.upload2.signature'
              : 'header.complete.signature',
        );
        completions++;
        return challenge('complete');
      });
      await pub.shouldExit(65);
      expect(uploads, 2);
      expect(completions, 2);
    },
  );

  for (final withAttestations in [false, true]) {
    test(
      'publish file details (with attestations: $withAttestations)',
      () async {
        final server = await servePackages();
        const path = '/org/Engineering/feeds/internal';
        final repository = '${server.url}$path/';
        await d
            .validPackage(
              pubspecExtras: {
                'publish_to': repository,
                'repository': 'https://example.test/project',
              },
            )
            .create();
        const attestations = '{ "attestations": [] }\n';
        if (withAttestations) {
          await d.file('attestations.json', attestations).create();
        }
        await runPub(
          args: ['lish', '--to-archive', p.join('..', 'release.tar.gz')],
        );
        await d.file('helper.dart', r"""
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  File(args.single + '.cwd').writeAsStringSync(Directory.current.path);
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
          args: [
            '--from-archive',
            d.path('release.tar.gz'),
            if (withAttestations) ...[
              '--with-attestation',
              d.path('attestations.json'),
            ],
          ],
        );
        await confirmPublish(pub);
        server.expect('GET', '$path/api/packages/versions/new', (request) {
          expect(request.headers['authorization'], 'Bearer access-token');
          return Response.found(
            Uri.parse(
              repository,
            ).resolve('/org/engineering/feeds/internal/form'),
          );
        });
        server.expect('GET', '/org/engineering/feeds/internal/form', (request) {
          expect(request.headers['authorization'], isNull);
          return Response.ok(
            jsonEncode({
              'url': '${server.url}/upload',
              'fields': <String, String>{},
              if (withAttestations)
                'attestationUrl': '${server.url}/attestations',
            }),
          );
        });
        if (withAttestations) {
          server.expect('POST', '/attestations', (request) async {
            expect(request.headers['authorization'], isNull);
            expect(await request.readAsString(), attestations);
            return Response.ok('');
          });
        }
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
        final cwd = File(d.path('calls.cwd')).readAsStringSync();
        expect(FileSystemEntity.identicalSync(cwd, d.path(appPath)), isTrue);
        final archive = File(d.path('release.tar.gz')).readAsBytesSync();
        expect(jsonDecode(File(d.path('calls')).readAsStringSync()), {
          'protocolVersion': 1,
          'action': 'acquire',
          'repository-url': repository,
          'interactive': false,
          'operation': 'publish',
          'package': 'test_pkg',
          'version': '1.0.0',
          'archive': {
            'length': archive.length,
            'sha256': sha256.convert(archive).toString(),
          },
          if (withAttestations)
            'attestations': {
              'length': utf8.encode(attestations).length,
              'sha256': sha256.convert(utf8.encode(attestations)).toString(),
            },
        });
      },
    );
  }
}
