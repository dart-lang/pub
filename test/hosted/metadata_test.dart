// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  forBothPubGetAndUpgrade((command) {
    test('sends metadata headers for a direct dependency', () async {
      await servePackages((builder) {
        builder.serve('foo', '1.0.0');
      });

      await d.appDir({'foo': '1.0.0'}).create();

      await pubCommand(command,
          silent: allOf([
            contains('X-Pub-OS: ${Platform.operatingSystem}'),
            contains('X-Pub-Command: ${command.name}'),
            contains('X-Pub-Session-ID:'),
            contains('X-Pub-Environment: test-environment'),

            // We should send the reason when we request the pubspec and when we
            // request the tarball.
            matchesMultiple('X-Pub-Reason: direct', 2),
            isNot(contains('X-Pub-Reason: dev')),
          ]));
    });

    test('no metadata headers when PUB_ENVIRONMENT is whitespace', () async {
      await servePackages((builder) {
        builder.serve('foo', '1.0.0');
      });

      await d.appDir({'foo': '1.0.0'}).create();

      await pubCommand(command,
          pubEnvironmentOverride: '   ',
          silent: allOf([
            contains('X-Pub-OS: ${Platform.operatingSystem}'),
            contains('X-Pub-Command: ${command.name}'),
            contains('X-Pub-Session-ID:'),
            isNot(contains('X-Pub-Environment')),

            // We should send the reason when we request the pubspec and when we
            // request the tarball.
            matchesMultiple('X-Pub-Reason: direct', 2),
            isNot(contains('X-Pub-Reason: dev')),
          ]));
    });

    test(
        'PUB_ENVIRONMENT w/ leading/trailing whitespace trim X-Pub-Environment',
        () async {
      await servePackages((builder) {
        builder.serve('foo', '1.0.0');
      });

      await d.appDir({'foo': '1.0.0'}).create();

      await pubCommand(command,
          pubEnvironmentOverride: ' some value  ',
          silent: allOf([
            contains('X-Pub-OS: ${Platform.operatingSystem}'),
            contains('X-Pub-Command: ${command.name}'),
            contains('X-Pub-Session-ID:'),
            contains('X-Pub-Environment: some value'),

            // We should send the reason when we request the pubspec and when we
            // request the tarball.
            matchesMultiple('X-Pub-Reason: direct', 2),
            isNot(contains('X-Pub-Reason: dev')),
          ]));
    });

    test('sends metadata headers for a dev dependency', () async {
      await servePackages((builder) {
        builder.serve('foo', '1.0.0');
      });

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dev_dependencies': {'foo': '1.0.0'}
        })
      ]).create();

      await pubCommand(command,
          silent: allOf([
            contains('X-Pub-OS: ${Platform.operatingSystem}'),
            contains('X-Pub-Command: ${command.name}'),
            contains('X-Pub-Session-ID:'),
            contains('X-Pub-Environment: test-environment'),

            // We should send the reason when we request the pubspec and when we
            // request the tarball.
            matchesMultiple('X-Pub-Reason: dev', 2),
            isNot(contains('X-Pub-Reason: direct')),
          ]));
    });

    test('sends metadata headers for a transitive dependency', () async {
      await servePackages((builder) {
        builder.serve('bar', '1.0.0');
      });

      await d.appDir({
        'foo': {'path': '../foo'}
      }).create();

      await d.dir('foo', [
        d.libPubspec('foo', '1.0.0', deps: {'bar': '1.0.0'})
      ]).create();

      await pubCommand(command,
          silent: allOf([
            contains('X-Pub-OS: ${Platform.operatingSystem}'),
            contains('X-Pub-Command: ${command.name}'),
            contains('X-Pub-Session-ID:'),
            contains('X-Pub-Environment: test-environment'),
            isNot(contains('X-Pub-Reason:')),
          ]));
    });

    test("doesn't send metadata headers to a foreign server", () async {
      var server = await PackageServer.start((builder) {
        builder.serve('foo', '1.0.0');
      });

      await d.appDir({
        'foo': {
          'version': '1.0.0',
          'hosted': {'name': 'foo', 'url': 'http://localhost:${server.port}'}
        }
      }).create();

      await pubCommand(command, silent: isNot(contains('X-Pub-')));
    });

    group('with CI environment set', () {
      setUp(() async {
        await servePackages((builder) {
          builder.serve('foo', '1.0.0');
        });

        await d.appDir({'foo': '1.0.0'}).create();
      });

      test('no PUB_ENVIRONMENT set', () async {
        await pubCommand(
          command,
          pubEnvironmentOverride: '',
          environment: {'CI': 'TRUE'},
          silent: allOf([
            contains('X-Pub-OS: ${Platform.operatingSystem}'),
            contains('X-Pub-Command: ${command.name}'),
            contains('X-Pub-Session-ID:'),
            contains('X-Pub-Environment: CI_set'),

            // We should send the reason when we request the pubspec and when we
            // request the tarball.
            matchesMultiple('X-Pub-Reason: direct', 2),
            isNot(contains('X-Pub-Reason: dev')),
          ]),
        );
      });

      test('with PUB_ENVIRONMENT set without leading period', () async {
        await pubCommand(
          command,
          pubEnvironmentOverride: 'some_value',
          environment: {'CI': 'TRUE'},
          silent: allOf([
            contains('X-Pub-OS: ${Platform.operatingSystem}'),
            contains('X-Pub-Command: ${command.name}'),
            contains('X-Pub-Session-ID:'),
            contains('X-Pub-Environment: CI_set.some_value'),

            // We should send the reason when we request the pubspec and when we
            // request the tarball.
            matchesMultiple('X-Pub-Reason: direct', 2),
            isNot(contains('X-Pub-Reason: dev')),
          ]),
        );
      });

      test('with PUB_ENVIRONMENT set with leading period', () async {
        await pubCommand(
          command,
          pubEnvironmentOverride: '.some_value',
          environment: {'CI': 'TRUE'},
          silent: allOf([
            contains('X-Pub-OS: ${Platform.operatingSystem}'),
            contains('X-Pub-Command: ${command.name}'),
            contains('X-Pub-Session-ID:'),
            contains('X-Pub-Environment: CI_set.some_value'),

            // We should send the reason when we request the pubspec and when we
            // request the tarball.
            matchesMultiple('X-Pub-Reason: direct', 2),
            isNot(contains('X-Pub-Reason: dev')),
          ]),
        );
      });
    });
  });
}
