// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../lish/utils.dart';
import '../test_pub.dart';

void main() {
  test('with a pre existing environment token authenticates', () async {
    await servePackages();
    await d.validPackage().create();
    await d.tokensFile({
      'version': 1,
      'hosted': [
        {'url': globalServer.url, 'env': 'TOKEN'},
      ]
    }).create();
    var pub = await startPublish(
      globalServer,
      overrideDefaultHostedServer: false,
      environment: {'TOKEN': 'access-token'},
    );
    await confirmPublish(pub);

    handleUploadForm(globalServer);

    await pub.shouldExit(1);
  });

  test('with a invalid environment token fails with error', () async {
    await servePackages();
    await d.validPackage().create();
    await d.tokensFile({
      'version': 1,
      'hosted': [
        {'url': globalServer.url, 'env': 'TOKEN'},
      ]
    }).create();
    await runPub(
      args: ['publish'],
      environment: {
        'TOKEN': 'access-token@' // '@' is not allowed in bearer tokens
      },
      error: contains(
        'Credential token for ${globalServer.url} is not a valid Bearer token.',
      ),
      exitCode: exit_codes.DATA,
    );
  });

  test('with a pre existing invalid opaque token fails with error', () async {
    await servePackages();
    await d.validPackage().create();
    await d.tokensFile({
      'version': 1,
      'hosted': [
        // Corrupted files can be created by earlier pub versions that did not
        // validate, or by manual edits.
        {
          'url': globalServer.url,
          'token': 'access-token@', // '@' is not allowed in bearer tokens
        },
      ]
    }).create();
    await runPub(
      args: ['publish'],
      environment: {
        'TOKEN': 'access-token@' // '@' is not allowed in bearer tokens
      },
      error: contains(
        'Credential token for ${globalServer.url} is not a valid Bearer token.',
      ),
      exitCode: exit_codes.DATA,
    );
  });

  test('with a pre existing opaque token authenticates', () async {
    await servePackages();
    await d.validPackage().create();
    await d.tokensFile({
      'version': 1,
      'hosted': [
        {'url': globalServer.url, 'token': 'access-token'},
      ]
    }).create();
    var pub = await startPublish(
      globalServer,
      overrideDefaultHostedServer: false,
    );
    await confirmPublish(pub);

    handleUploadForm(globalServer);

    await pub.shouldExit(1);
  });
}
