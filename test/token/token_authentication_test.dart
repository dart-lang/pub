// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../lish/utils.dart';
import '../test_pub.dart';

void main() {
  setUp(d.validPackage.create);

  test('with a pre existing environment token authenticates', () async {
    await servePackages();
    await d.tokensFile({
      'version': 1,
      'hosted': [
        {'url': globalServer.url, 'env': 'TOKEN'},
      ]
    }).create();
    var pub = await startPublish(globalServer,
        authMethod: 'token', environment: {'TOKEN': 'access token'});
    await confirmPublish(pub);

    handleUploadForm(globalServer);

    await pub.shouldExit(1);
  });

  test('with a pre existing opaque token authenticates', () async {
    await servePackages();
    await d.tokensFile({
      'version': 1,
      'hosted': [
        {'url': globalServer.url, 'token': 'access token'},
      ]
    }).create();
    var pub = await startPublish(globalServer, authMethod: 'token');
    await confirmPublish(pub);

    handleUploadForm(globalServer);

    await pub.shouldExit(1);
  });
}
