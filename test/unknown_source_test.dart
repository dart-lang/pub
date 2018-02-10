// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE d.file.

@Skip()

import 'dart:convert';

import 'package:test/test.dart';

import 'descriptor.dart' as d;
import 'test_pub.dart';

main() {
  forBothPubGetAndUpgrade((command) {
    test('fails gracefully on a dependency from an unknown source', () async {
      await d.appDir({
        "foo": {"bad": "foo"}
      }).create();

      await pubCommand(command,
          error: 'Package myapp depends on foo from unknown source "bad".');
    });

    test(
        'fails gracefully on transitive dependency from an unknown '
        'source', () async {
      await d.dir('foo', [
        d.libDir('foo', 'foo 0.0.1'),
        d.libPubspec('foo', '0.0.1', deps: {
          "bar": {"bad": "bar"}
        })
      ]).create();

      await d.appDir({
        "foo": {"path": "../foo"}
      }).create();

      await pubCommand(command,
          error: 'Package foo depends on bar from unknown source "bad".');
    });

    test('ignores unknown source in lockfile', () async {
      await d
          .dir('foo', [d.libDir('foo'), d.libPubspec('foo', '0.0.1')]).create();

      // Depend on "foo" from a valid source.
      await d.dir(appPath, [
        d.appPubspec({
          "foo": {"path": "../foo"}
        })
      ]).create();

      // But lock it to a bad one.
      await d.dir(appPath, [
        d.file(
            "pubspec.lock",
            JSON.encode({
              'packages': {
                'foo': {
                  'version': '0.0.0',
                  'source': 'bad',
                  'description': {'name': 'foo'}
                }
              }
            }))
      ]).create();

      await pubCommand(command);

      // Should upgrade to the new one.
      await d.appPackagesFile({"foo": "../foo"}).validate();
    });
  });
}
