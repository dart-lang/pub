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
    [String accessToken = 'access token']) async {
  await expectLater(
      pub.stdout,
      emits('Pub needs your authorization to upload packages on your '
          'behalf.'));

  var line = await pub.stdout.next;
  var match =
      RegExp(r'[?&]redirect_uri=([0-9a-zA-Z.%+-]+)[$&]').firstMatch(line);
  expect(match, isNotNull);

  var redirectUrl = Uri.parse(Uri.decodeComponent(match.group(1)));
  redirectUrl = _addQueryParameters(redirectUrl, {'code': 'access code'});

  // Expect the /token request
  handleAccessTokenRequest(server, accessToken);

  // Call the redirect url as the browser would otherwise do after successful
  // sign-in with Google account.
  var response =
      await (http.Request('GET', redirectUrl)..followRedirects = false).send();
  expect(response.headers['location'],
      equals('https://pub.dartlang.org/authorized'));
}

void handleAccessTokenRequest(ShelfTestServer server, String accessToken) {
  server.handler.expect('POST', '/token', (request) async {
    var body = await request.readAsString();
    expect(body, matches(RegExp(r'(^|&)code=access\+code(&|$)')));

    return shelf.Response.ok(
        jsonEncode({'access_token': accessToken, 'token_type': 'bearer'}),
        headers: {'content-type': 'application/json'});
  });
}

/// Adds additional query parameters to [url], overwriting the original
/// parameters if a name conflict occurs.
Uri _addQueryParameters(Uri url, Map<String, String> parameters) {
  var queryMap = queryToMap(url.query);
  queryMap.addAll(parameters);
  return url.resolve('?${_mapToQuery(queryMap)}');
}

/// Convert a [Map] from parameter names to values to a URL query string.
String _mapToQuery(Map<String, String> map) {
  var pairs = <List<String>>[];
  map.forEach((key, value) {
    key = Uri.encodeQueryComponent(key);
    value = (value == null || value.isEmpty)
        ? null
        : Uri.encodeQueryComponent(value);
    pairs.add([key, value]);
  });
  return pairs.map((pair) {
    if (pair[1] == null) return pair[0];
    return '${pair[0]}=${pair[1]}';
  }).join('&');
}
