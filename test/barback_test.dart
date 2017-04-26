// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:barback/barback.dart';
import 'package:pub/src/barback.dart';
import 'package:test/test.dart';

void main() {
  group('importUriToId', () {
    test('returns null for dart: imports', () {
      expect(importUriToAssetId(new AssetId('a', 'lib/a.dart'), 'dart:async'),
          isNull);
    });

    test('relative imports can be resolved', () {
      expect(importUriToAssetId(new AssetId('a', 'web/a.dart'), 'b.dart'),
          new AssetId('a', 'web/b.dart'));
      expect(importUriToAssetId(new AssetId('a', 'lib/a.dart'), 'b.dart'),
          new AssetId('a', 'lib/b.dart'));
      expect(importUriToAssetId(new AssetId('a', 'lib/a/a.dart'), '../a.dart'),
          new AssetId('a', 'lib/a.dart'));
      expect(importUriToAssetId(new AssetId('a', 'lib/a.dart'), 'a/a.dart'),
          new AssetId('a', 'lib/a/a.dart'));
    });

    test('throws for invalid relative imports', () {
      expect(
          () =>
              importUriToAssetId(new AssetId('a', 'lib/a.dart'), '../foo.dart'),
          throwsArgumentError,
          reason: 'Relative imports can\'t reach outside lib.');

      expect(
          () => importUriToAssetId(
              new AssetId('a', 'web/a.dart'), '../lib/foo.dart'),
          throwsArgumentError,
          reason: 'Relative imports can\'t reach from web to lib.');

      expect(
          () => importUriToAssetId(
              new AssetId('a', 'lib/a.dart'), '../web/foo.dart'),
          throwsArgumentError,
          reason: 'Relative imports can\'t reach from lib to web.');
    });

    test('package: imports can be resolved', () {
      expect(
          importUriToAssetId(
              new AssetId('a', 'lib/a.dart'), 'package:b/b.dart'),
          new AssetId('b', 'lib/b.dart'));
    });

    test('Invalid package: imports throw', () {
      expect(
          () => importUriToAssetId(
              new AssetId('a', 'lib/a.dart'), 'package:b/../b.dart'),
          throwsArgumentError);
    });
  });
}
