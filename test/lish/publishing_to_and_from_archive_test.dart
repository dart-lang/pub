// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:pub/src/exit_codes.dart';
import 'package:pub/src/path.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

void main() {
  test('Can publish into and from archive', () async {
    final server = await servePackages();
    await d.validPackage().create();
    await d.credentialsFile(server, 'access-token').create();
    await runPub(
      args: ['lish', '--to-archive', p.join('..', 'archive.tar.gz')],
      output: contains(
        'Wrote package archive at ${p.join('..', 'archive.tar.gz')}',
      ),
    );
    expect(File(d.path('archive.tar.gz')).existsSync(), isTrue);

    server.expect('GET', '/create', (request) {
      return Response.ok(
        jsonEncode({
          'success': {'message': 'Package test_pkg 1.0.0 uploaded!'},
        }),
      );
    });

    final pub = await startPublish(
      server,
      args: ['--from-archive', 'archive.tar.gz'],
      // Run outside the appPath to make sure we are not publishing that dir.
      workingDirectory: d.sandbox,
    );

    expect(pub.stdout, emitsThrough('Publishing from archive: archive.tar.gz'));
    await confirmPublish(pub);

    handleUploadForm(server);
    handleUpload(server);

    expect(pub.stdout, emitsThrough(startsWith('Uploading...')));
    expect(
      pub.stdout,
      emits('Message from server: Package test_pkg 1.0.0 uploaded!'),
    );
    await pub.shouldExit(SUCCESS);
  });

  test('Can extract self-published archive', () async {
    await d.validPackage().create();

    await runPub(
      args: ['lish', '--to-archive', p.join('..', 'archive.tar.gz')],
      output: contains(
        'Wrote package archive at ${p.join('..', 'archive.tar.gz')}',
      ),
    );
    expect(File(d.path('archive.tar.gz')).existsSync(), isTrue);
    await runPub(args: ['cache', 'preload', p.join('..', 'archive.tar.gz')]);
  });

  test('Can publish from archive with attestation bundle', () async {
    final server = await servePackages();
    await d
        .validPackage(
          pubspecExtras: {
            'repository': 'https://github.com/dart-lang/test_pkg',
          },
        )
        .create();
    await d.credentialsFile(server, 'access-token').create();
    await runPub(
      args: [
        'lish',
        '--skip-validation',
        '--to-archive',
        p.join('..', 'archive.tar.gz'),
      ],
    );

    final bundleContent = '{"mediaType": "sigstore"}';
    final bundlePath = p.join(d.sandbox, 'bundle.sigstore.json');
    File(bundlePath).writeAsStringSync(bundleContent);

    server.expect('POST', '/create', (request) async {
      expect(request.headers['content-type'], startsWith('application/json'));
      final body = jsonDecode(await request.readAsString());
      expect(body, {'attestation': jsonDecode(bundleContent)});
      return Response.ok(
        jsonEncode({
          'success': {
            'message': 'Package test_pkg 1.0.0 with attestation uploaded!',
          },
        }),
      );
    });

    final pub = await startPublish(
      server,
      args: [
        '--from-archive',
        'archive.tar.gz',
        '--with-attestation',
        bundlePath,
      ],
      workingDirectory: d.sandbox,
    );

    expect(pub.stdout, emitsThrough('Publishing from archive: archive.tar.gz'));
    await confirmPublish(pub);

    handleUploadForm(server);
    server.handle('/upload', (request) async {
      await request.read().drain<void>();
      return Response.found(Uri.parse(server.url).resolve('/create'));
    });

    expect(pub.stdout, emitsThrough(startsWith('Uploading...')));
    expect(
      pub.stdout,
      emits(
        'Message from server: '
        'Package test_pkg 1.0.0 with attestation uploaded!',
      ),
    );
    await pub.shouldExit(SUCCESS);
  });

  test('Fails when publishing with attestation to a server that does not '
      'support it', () async {
    final server = await servePackages();
    await d
        .validPackage(
          pubspecExtras: {
            'repository': 'https://github.com/dart-lang/test_pkg',
          },
        )
        .create();
    await d.credentialsFile(server, 'access-token').create();
    await runPub(
      args: [
        'lish',
        '--skip-validation',
        '--to-archive',
        p.join('..', 'archive.tar.gz'),
      ],
    );

    final bundlePath = p.join(d.sandbox, 'bundle.sigstore.json');
    File(bundlePath).writeAsStringSync('{"mediaType": "sigstore"}');

    server.expect('POST', '/create', (request) {
      return Response(405);
    });

    final pub = await startPublish(
      server,
      args: [
        '--from-archive',
        'archive.tar.gz',
        '--with-attestation',
        bundlePath,
      ],
      workingDirectory: d.sandbox,
    );

    expect(pub.stdout, emitsThrough('Publishing from archive: archive.tar.gz'));
    await confirmPublish(pub);

    handleUploadForm(server);
    server.handle('/upload', (request) async {
      await request.read().drain<void>();
      return Response.found(Uri.parse(server.url).resolve('/create'));
    });

    expect(pub.stdout, emitsThrough(startsWith('Uploading...')));
    await pub.shouldExit(DATA);
    expect(
      pub.stderr,
      emitsThrough(contains('does not support publishing with attestations')),
    );
  });

  test(
    'Fails when publishing with attestation without repository in pubspec',
    () async {
      await d.validPackage().create();
      await runPub(
        args: [
          'lish',
          '--skip-validation',
          '--to-archive',
          p.join('..', 'archive.tar.gz'),
        ],
      );

      final bundlePath = p.join(d.sandbox, 'bundle.sigstore.json');
      File(bundlePath).writeAsStringSync('{}');

      await runPub(
        args: [
          'lish',
          '--from-archive',
          p.join(d.sandbox, 'archive.tar.gz'),
          '--with-attestation',
          bundlePath,
        ],
        error: contains(
          'A repository must be specified in the "repository" field',
        ),
        exitCode: DATA,
        workingDirectory: d.sandbox,
      );
    },
  );

  test(
    'Allows publishing from archive with attestation and non-GitHub repository',
    () async {
      final server = await servePackages();
      await d
          .validPackage(
            pubspecExtras: {
              'repository': 'https://gitlab.com/dart-lang/test_pkg',
            },
          )
          .create();
      await d.credentialsFile(server, 'access-token').create();
      await runPub(
        args: [
          'lish',
          '--skip-validation',
          '--to-archive',
          p.join('..', 'archive.tar.gz'),
        ],
      );

      final bundleContent = '{"mediaType": "sigstore"}';
      final bundlePath = p.join(d.sandbox, 'bundle.sigstore.json');
      File(bundlePath).writeAsStringSync(bundleContent);

      server.expect('POST', '/create', (request) async {
        return Response.ok(
          jsonEncode({
            'success': {
              'message': 'Package test_pkg 1.0.0 with attestation uploaded!',
            },
          }),
        );
      });

      final pub = await startPublish(
        server,
        args: [
          '--from-archive',
          'archive.tar.gz',
          '--with-attestation',
          bundlePath,
        ],
        workingDirectory: d.sandbox,
      );

      expect(
        pub.stdout,
        emitsThrough('Publishing from archive: archive.tar.gz'),
      );
      await confirmPublish(pub);

      handleUploadForm(server);
      server.handle('/upload', (request) async {
        await request.read().drain<void>();
        return Response.found(Uri.parse(server.url).resolve('/create'));
      });

      expect(pub.stdout, emitsThrough(startsWith('Uploading...')));
      await pub.shouldExit(SUCCESS);
    },
  );

  test(
    'Fails when --with-attestation is used without --from-archive',
    () async {
      await d.validPackage().create();
      await runPub(
        args: ['lish', '--with-attestation', 'bundle.json'],
        error: contains(
          '`--with-attestation` can only be used with `--from-archive`.',
        ),
        exitCode: USAGE,
      );
    },
  );

  test('Fails when attestation file is empty', () async {
    await d
        .validPackage(
          pubspecExtras: {
            'repository': 'https://github.com/dart-lang/test_pkg',
          },
        )
        .create();
    await runPub(
      args: [
        'lish',
        '--skip-validation',
        '--to-archive',
        p.join('..', 'archive.tar.gz'),
      ],
    );

    final bundlePath = p.join(d.sandbox, 'bundle.sigstore.json');
    File(bundlePath).writeAsStringSync('');

    await runPub(
      args: [
        'lish',
        '--from-archive',
        p.join(d.sandbox, 'archive.tar.gz'),
        '--with-attestation',
        bundlePath,
      ],
      error: contains('The attestation file "$bundlePath" is empty.'),
      exitCode: DATA,
      workingDirectory: d.sandbox,
    );
  });

  test('Fails when attestation file is not valid JSON', () async {
    await d
        .validPackage(
          pubspecExtras: {
            'repository': 'https://github.com/dart-lang/test_pkg',
          },
        )
        .create();
    await runPub(
      args: [
        'lish',
        '--skip-validation',
        '--to-archive',
        p.join('..', 'archive.tar.gz'),
      ],
    );

    final bundlePath = p.join(d.sandbox, 'bundle.sigstore.json');
    File(bundlePath).writeAsStringSync('not-json');

    await runPub(
      args: [
        'lish',
        '--from-archive',
        p.join(d.sandbox, 'archive.tar.gz'),
        '--with-attestation',
        bundlePath,
      ],
      error: contains('is not valid JSON:'),
      exitCode: DATA,
      workingDirectory: d.sandbox,
    );
  });

  test('Fails when attestation file is not a JSON object', () async {
    await d
        .validPackage(
          pubspecExtras: {
            'repository': 'https://github.com/dart-lang/test_pkg',
          },
        )
        .create();
    await runPub(
      args: [
        'lish',
        '--skip-validation',
        '--to-archive',
        p.join('..', 'archive.tar.gz'),
      ],
    );

    final bundlePath = p.join(d.sandbox, 'bundle.sigstore.json');
    File(bundlePath).writeAsStringSync('["not", "a", "map"]');

    await runPub(
      args: [
        'lish',
        '--from-archive',
        p.join(d.sandbox, 'archive.tar.gz'),
        '--with-attestation',
        bundlePath,
      ],
      error: contains('must contain a JSON object.'),
      exitCode: DATA,
      workingDirectory: d.sandbox,
    );
  });
}
