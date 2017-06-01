// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_test_handler/shelf_test_handler.dart';
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

import 'package:pub/src/utils.dart';

Future authorizePub(TestProcess pub, ShelfTestServer server,
    [String accessToken = "access token"]) async {
  expect(
      pub.stdout,
      emits('Pub needs your authorization to upload packages on your '
          'behalf.'));

  var line = await pub.stdout.next;
  var match =
      new RegExp(r'[?&]redirect_uri=([0-9a-zA-Z.%+-]+)[$&]').firstMatch(line);
  expect(match, isNotNull);

  var redirectUrl = Uri.parse(Uri.decodeComponent(match.group(1)));
  redirectUrl = addQueryParameters(redirectUrl, {'code': 'access code'});
  var response = await (new http.Request('GET', redirectUrl)
        ..followRedirects = false)
      .send();
  expect(response.headers['location'],
      equals('http://pub.dartlang.org/authorized'));

  handleAccessTokenRequest(server, accessToken);
}

void handleAccessTokenRequest(ShelfTestServer server, String accessToken) {
  server.handler.expect('POST', '/token', (request) async {
    var body = await request.readAsString();
    expect(body, matches(new RegExp(r'(^|&)code=access\+code(&|$)')));

    return new shelf.Response.ok(
        JSON.encode({"access_token": accessToken, "token_type": "bearer"}),
        headers: {'content-type': 'application/json'});
  });
}
