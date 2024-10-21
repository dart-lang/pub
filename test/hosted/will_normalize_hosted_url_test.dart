// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:http/http.dart' as http;
import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  forBothPubGetAndUpgrade((command) {
    test('does not require slash on bare domain', () async {
      final server = await servePackages();
      server.serve('foo', '1.2.3');
      // All the tests in this file assumes that [globalServer.url]
      // will be on the form:
      //   http://localhost:<port>
      // In particular, that it doesn't contain anything path segment.
      expect(Uri.parse(globalServer.url).path, isEmpty);

      await d.dir(appPath, [
        d.appPubspec(
          dependencies: {
            'foo': {
              'hosted': {'name': 'foo', 'url': globalServer.url},
            },
          },
        ),
      ]).create();

      await pubCommand(
        command,
        silent: contains('${globalServer.url}/api/packages/foo'),
      );
    });

    test('normalizes extra slash', () async {
      final server = await servePackages();
      server.serve('foo', '1.2.3');

      await d.dir(appPath, [
        d.appPubspec(
          dependencies: {
            'foo': {
              'hosted': {'name': 'foo', 'url': '${globalServer.url}/'},
            },
          },
        ),
      ]).create();

      await pubCommand(
        command,
        silent: contains('${globalServer.url}/api/packages/foo'),
      );
    });

    test('cannot normalize double slash', () async {
      final server = await servePackages();
      server.serve('foo', '1.2.3');
      globalServer.expect(
        'GET',
        '//api/packages/foo',
        (request) => Response.notFound(''),
      );

      await d.dir(appPath, [
        d.appPubspec(
          dependencies: {
            'foo': {
              'hosted': {'name': 'foo', 'url': '${globalServer.url}//'},
            },
          },
        ),
      ]).create();

      await pubCommand(
        command,
        error: contains('could not find package foo at ${globalServer.url}//'),
        exitCode: exit_codes.UNAVAILABLE,
      );
    });

    /// Proxy request for '/my-folder/...' -> '/...'
    ///
    /// This is a bit of a hack, to easily test if hosted pub URLs with a path
    /// segment works and if the slashes are normalized.
    void proxyMyFolderToRoot() {
      globalServer.handle(
        RegExp('/my-folder/.*'),
        (r) async {
          if (r.method != 'GET' && r.method != 'HEAD') {
            return Response.forbidden(null);
          }
          final path = r.requestedUri.path.substring('/my-folder/'.length);
          final res = await http.get(
            Uri.parse('${globalServer.url}/$path'),
          );
          return Response(
            res.statusCode,
            body: res.bodyBytes,
            headers: {
              'Content-Type': res.headers['content-type']!,
            },
          );
        },
      );
    }

    test('will use normalized url with path', () async {
      final server = await servePackages();
      server.serve('foo', '1.2.3');
      proxyMyFolderToRoot();

      // testing with a normalized URL
      final testUrl = '${globalServer.url}/my-folder/';
      final normalizedUrl = '${globalServer.url}/my-folder/';

      await d.dir(appPath, [
        d.appPubspec(
          dependencies: {
            'foo': {
              'hosted': {'name': 'foo', 'url': testUrl},
            },
          },
        ),
      ]).create();

      await pubCommand(command);

      await d.dir(appPath, [
        d.file('pubspec.lock', contains('"$normalizedUrl"')),
      ]).validate();
    });

    test('will normalize url with path by adding slash', () async {
      final server = await servePackages();
      server.serve('foo', '1.2.3');
      proxyMyFolderToRoot();

      // Testing with a URL that is missing the slash.
      final testUrl = '${globalServer.url}/my-folder';
      final normalizedUrl = '${globalServer.url}/my-folder/';

      await d.dir(appPath, [
        d.appPubspec(
          dependencies: {
            'foo': {
              'hosted': {'name': 'foo', 'url': testUrl},
            },
          },
        ),
      ]).create();

      await pubCommand(command);

      await d.dir(appPath, [
        d.file('pubspec.lock', contains('"$normalizedUrl"')),
      ]).validate();
    });
  });
}
