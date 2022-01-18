// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('with an existing credentials file, deletes it.', () async {
    await servePackages();
    await d
        .credentialsFile(globalServer, 'access token',
            refreshToken: 'refresh token',
            expiration: DateTime.now().add(Duration(hours: 1)))
        .create();

    await runPub(
        args: ['logout'], output: contains('Logging out of pub.dartlang.org.'));

    await d.dir(configPath, [d.nothing('pub-credentials.json')]).validate();
  });

  test(
      'with an existing credentials file stored in the legacy location, deletes both.',
      () async {
    await servePackages();
    await d
        .credentialsFile(
          globalServer,
          'access token',
          refreshToken: 'refresh token',
          expiration: DateTime.now().add(Duration(hours: 1)),
        )
        .create();

    await d
        .legacyCredentialsFile(
          globalServer,
          'access token',
          refreshToken: 'refresh token',
          expiration: DateTime.now().add(Duration(hours: 1)),
        )
        .create();

    await runPub(
      args: ['logout'],
      output: allOf(
        [
          contains('Logging out of pub.dartlang.org.'),
          contains('Also deleting legacy credentials at ')
        ],
      ),
    );

    await d.dir(cachePath, [d.nothing('credentials.json')]).validate();
    await d.dir(configPath, [d.nothing('pub-credentials.json')]).validate();
  });
  test('with no existing credentials.json, notifies.', () async {
    await d.dir(configPath, [d.nothing('pub-credentials.json')]).create();
    await runPub(
        args: ['logout'], output: contains('No existing credentials file'));

    await d.dir(configPath, [d.nothing('pub-credentials.json')]).validate();
  });
}
