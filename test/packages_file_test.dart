// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart' as exit_codes;

import 'package:test/test.dart';

import 'descriptor.dart' as d;
import 'test_pub.dart';

void main() {
  forBothPubGetAndUpgrade((command) {
    test('.packages file is created with flag', () async {
      await servePackages()
        ..serve('foo', '1.2.3',
            deps: {'baz': '2.2.2'}, contents: [d.dir('lib', [])])
        ..serve('bar', '3.2.1', contents: [d.dir('lib', [])])
        ..serve('baz', '2.2.2',
            deps: {'bar': '3.2.1'}, contents: [d.dir('lib', [])]);

      await d.dir(appPath, [
        d.appPubspec({'foo': '1.2.3'}),
        d.dir('lib')
      ]).create();

      await pubCommand(command, args: ['--packages-file']);

      await d.dir(appPath, [
        d.packagesFile(
            {'foo': '1.2.3', 'bar': '3.2.1', 'baz': '2.2.2', 'myapp': '.'}),
      ]).validate();
    });

    test('.packages file is overwritten with flag', () async {
      await servePackages()
        ..serve('foo', '1.2.3',
            deps: {'baz': '2.2.2'}, contents: [d.dir('lib', [])])
        ..serve('bar', '3.2.1', contents: [d.dir('lib', [])])
        ..serve('baz', '2.2.2',
            deps: {'bar': '3.2.1'}, contents: [d.dir('lib', [])]);

      await d.dir(appPath, [
        d.appPubspec({'foo': '1.2.3'}),
        d.dir('lib')
      ]).create();

      var oldFile = d.dir(appPath, [
        d.packagesFile({'notFoo': '9.9.9'})
      ]);
      await oldFile.create();
      await oldFile.validate(); // Sanity-check that file was created correctly.

      await pubCommand(command, args: ['--packages-file']);

      await d.dir(appPath, [
        d.packagesFile(
            {'foo': '1.2.3', 'bar': '3.2.1', 'baz': '2.2.2', 'myapp': '.'})
      ]).validate();
    });

    test('.packages file is not created if pub command fails with flag',
        () async {
      await d.dir(appPath, [
        d.appPubspec({'foo': '1.2.3'}),
        d.dir('lib')
      ]).create();

      await pubCommand(command,
          args: ['--offline', '--packages-file'],
          error: equalsIgnoringWhitespace("""
            Because myapp depends on foo any which doesn't exist (could not find
              package foo in cache), version solving failed.

            Try again without --offline!
          """),
          exitCode: exit_codes.UNAVAILABLE);

      await d.dir(appPath, [d.nothing('.packages')]).validate();
    });

    test('.packages file has relative path to path dependency with flag',
        () async {
      await servePackages()
        ..serve('foo', '1.2.3',
            deps: {'baz': 'any'}, contents: [d.dir('lib', [])])
        ..serve('baz', '9.9.9', deps: {}, contents: [d.dir('lib', [])]);

      await d.dir('local_baz', [
        d.libDir('baz', 'baz 3.2.1'),
        d.libPubspec('baz', '3.2.1')
      ]).create();

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependencies': {
            'foo': '^1.2.3',
          },
          'dependency_overrides': {
            'baz': {'path': '../local_baz'},
          }
        }),
        d.dir('lib')
      ]).create();

      await pubCommand(command, args: ['--packages-file']);

      await d.dir(appPath, [
        d.packagesFile({'myapp': '.', 'baz': '../local_baz', 'foo': '1.2.3'}),
      ]).validate();
    });
  });
}
