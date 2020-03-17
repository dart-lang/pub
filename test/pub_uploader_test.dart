// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_test_handler/shelf_test_handler.dart';
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

import 'descriptor.dart' as d;
import 'test_pub.dart';

const _usageString = '''
Manage uploaders for a package on pub.dartlang.org.

Usage: pub uploader [options] {add/remove} <email>
-h, --help       Print this usage information.
    --server     The package server on which the package is hosted.
                 (defaults to "https://pub.dartlang.org")
    --package    The package whose uploaders will be modified.
                 (defaults to the current package)

Run "pub help" to see global options.
See https://dart.dev/tools/pub/cmd/pub-uploader for detailed documentation.
''';

Future<TestProcess> startPubUploader(
    ShelfTestServer server, List<String> args) {
  var tokenEndpoint = server.url.resolve('/token').toString();
  var allArgs = ['uploader', '--server', tokenEndpoint, ...args];
  return startPub(args: allArgs, tokenEndpoint: tokenEndpoint);
}

void main() {
  group('displays usage', () {
    test('when run with no arguments', () {
      return runPub(
          args: ['uploader'], output: _usageString, exitCode: exit_codes.USAGE);
    });

    test('when run with only a command', () {
      return runPub(
          args: ['uploader', 'add'],
          output: _usageString,
          exitCode: exit_codes.USAGE);
    });

    test('when run with an invalid command', () {
      return runPub(
          args: ['uploader', 'foo', 'email'],
          output: _usageString,
          exitCode: exit_codes.USAGE);
    });
  });

  test('adds an uploader', () async {
    var server = await ShelfTestServer.create();
    await d.credentialsFile(server, 'access token').create();
    var pub =
        await startPubUploader(server, ['--package', 'pkg', 'add', 'email']);

    server.handler.expect('POST', '/api/packages/pkg/uploaders', (request) {
      return request.readAsString().then((body) {
        expect(body, equals('email=email'));

        return shelf.Response.ok(
            jsonEncode({
              'success': {'message': 'Good job!'}
            }),
            headers: {'content-type': 'application/json'});
      });
    });

    expect(pub.stdout, emits('Good job!'));
    await pub.shouldExit(exit_codes.SUCCESS);
  });

  test('removes an uploader', () async {
    var server = await ShelfTestServer.create();
    await d.credentialsFile(server, 'access token').create();
    var pub =
        await startPubUploader(server, ['--package', 'pkg', 'remove', 'email']);

    server.handler.expect('DELETE', '/api/packages/pkg/uploaders/email',
        (request) {
      return shelf.Response.ok(
          jsonEncode({
            'success': {'message': 'Good job!'}
          }),
          headers: {'content-type': 'application/json'});
    });

    expect(pub.stdout, emits('Good job!'));
    await pub.shouldExit(exit_codes.SUCCESS);
  });

  test('defaults to the current package', () async {
    await d.validPackage.create();

    var server = await ShelfTestServer.create();
    await d.credentialsFile(server, 'access token').create();
    var pub = await startPubUploader(server, ['add', 'email']);

    server.handler.expect('POST', '/api/packages/test_pkg/uploaders',
        (request) {
      return shelf.Response.ok(
          jsonEncode({
            'success': {'message': 'Good job!'}
          }),
          headers: {'content-type': 'application/json'});
    });

    expect(pub.stdout, emits('Good job!'));
    await pub.shouldExit(exit_codes.SUCCESS);
  });

  test('add provides an error', () async {
    var server = await ShelfTestServer.create();
    await d.credentialsFile(server, 'access token').create();
    var pub =
        await startPubUploader(server, ['--package', 'pkg', 'add', 'email']);

    server.handler.expect('POST', '/api/packages/pkg/uploaders', (request) {
      return shelf.Response(400,
          body: jsonEncode({
            'error': {'message': 'Bad job!'}
          }),
          headers: {'content-type': 'application/json'});
    });

    expect(pub.stderr, emits('Bad job!'));
    await pub.shouldExit(1);
  });

  test('remove provides an error', () async {
    var server = await ShelfTestServer.create();
    await d.credentialsFile(server, 'access token').create();
    var pub = await startPubUploader(
        server, ['--package', 'pkg', 'remove', 'e/mail']);

    server.handler.expect('DELETE', '/api/packages/pkg/uploaders/e%2Fmail',
        (request) {
      return shelf.Response(400,
          body: jsonEncode({
            'error': {'message': 'Bad job!'}
          }),
          headers: {'content-type': 'application/json'});
    });

    expect(pub.stderr, emits('Bad job!'));
    await pub.shouldExit(1);
  });

  test('add provides invalid JSON', () async {
    var server = await ShelfTestServer.create();
    await d.credentialsFile(server, 'access token').create();
    var pub =
        await startPubUploader(server, ['--package', 'pkg', 'add', 'email']);

    server.handler.expect('POST', '/api/packages/pkg/uploaders',
        (request) => shelf.Response.ok('{not json'));

    expect(
        pub.stderr,
        emitsLines('Invalid server response:\n'
            '{not json'));
    await pub.shouldExit(1);
  });

  test('remove provides invalid JSON', () async {
    var server = await ShelfTestServer.create();
    await d.credentialsFile(server, 'access token').create();
    var pub =
        await startPubUploader(server, ['--package', 'pkg', 'remove', 'email']);

    server.handler.expect('DELETE', '/api/packages/pkg/uploaders/email',
        (request) => shelf.Response.ok('{not json'));

    expect(
        pub.stderr,
        emitsLines('Invalid server response:\n'
            '{not json'));
    await pub.shouldExit(1);
  });
}
