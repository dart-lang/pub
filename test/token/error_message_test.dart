// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void respondWithWwwAuthenticate(String headerValue) {
  globalServer.expect('GET', '/api/packages/versions/new', (request) {
    return shelf.Response(403, headers: {'www-authenticate': headerValue});
  });
}

Future<void> expectPubErrorMessage(dynamic matcher) {
  return runPub(
    args: ['lish'],
    environment: {
      'PUB_HOSTED_URL': globalServer.url,
      '_PUB_TEST_AUTH_METHOD': 'token',
    },
    exitCode: 65,
    input: ['y'],
    error: matcher,
  );
}

void main() {
  setUp(() async {
    await d.validPackage().create();
    await servePackages();
    await d.tokensFile({
      'version': 1,
      'hosted': [
        {'url': globalServer.url, 'token': 'access-token'},
      ]
    }).create();
  });

  test('prints www-authenticate message', () async {
    respondWithWwwAuthenticate('bearer realm="pub", message="custom message"');
    await expectPubErrorMessage(contains('custom message'));
  });

  test('sanitizes and prints dirty www-authenticate message', () {
    // Unable to test this case because shelf does not allow characters [1]
    // that pub cli supposed to sanitize.
    //
    // [1] https://github.com/dart-lang/sdk/blob/main/sdk/lib/_http/http_headers.dart#L653-L662
  });

  test('trims and prints long www-authenticate message', () async {
    var message = List.generate(2048, (_) => 'a').join();

    respondWithWwwAuthenticate('bearer realm="pub", message="$message"');
    await expectPubErrorMessage(
      allOf(
        isNot(contains(message)),
        contains(message.substring(0, 1024)),
      ),
    );
  });

  test('does not prints message if realm is not equals to pub', () async {
    respondWithWwwAuthenticate('bearer realm="web", message="custom message"');
    await expectPubErrorMessage(isNot(contains('custom message')));
  });

  test('does not prints message if challenge is not equals to bearer',
      () async {
    respondWithWwwAuthenticate('basic realm="pub", message="custom message"');
    await expectPubErrorMessage(isNot(contains('custom message')));
  });

  test('prints message for bearer challenge for pub realm only', () async {
    respondWithWwwAuthenticate(
      'basic realm="pub", message="enter username and password", '
      'newAuth message="use web portal to login", '
      'bearer realm="api", message="contact IT dept to enroll", '
      'bearer realm="pub", '
      'bearer realm="pub", message="pub realm message"',
    );
    await expectPubErrorMessage(contains('pub realm message'));
  });
}
