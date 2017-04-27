// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:barback/barback.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:pub/src/barback/dartdevc/temp_environment.dart';
import 'package:pub/src/io.dart';

void main() {
  test('Can create and delete a temp environment', () async {
    Map<AssetId, List<int>> allAssets = [
      'dep|lib/dep.dart',
      'myapp|lib/myapp.dart',
      'myapp|web/main.dart',
    ].fold({}, (assets, serializedId) {
      assets[new AssetId.parse(serializedId)] = serializedId.codeUnits;
      return assets;
    });

    var tempEnv = await TempEnvironment.create(
        allAssets.keys, (id) => new Stream.fromIterable([allAssets[id]]));

    expect(p.isWithin(Directory.systemTemp.path, tempEnv.tempDir.path), isTrue);

    for (var id in allAssets.keys) {
      var file = tempEnv.fileFor(id);
      expect(file.existsSync(), isTrue);
      expect(file.readAsStringSync(), equals('$id'));

      var relativeFilePath = p.relative(file.path, from: tempEnv.tempDir.path);
      if (topLevelDir(id.path) == 'lib') {
        var packagesPath =
            p.join('packages', id.package, p.relative(id.path, from: 'lib'));
        expect(relativeFilePath, equals(packagesPath));
      } else {
        expect(relativeFilePath, equals(id.path));
      }
    }

    await tempEnv.delete();

    for (var id in allAssets.keys) {
      var file = tempEnv.fileFor(id);
      expect(file.existsSync(), isFalse);
    }
    expect(tempEnv.tempDir.existsSync(), isFalse);
  });
}
