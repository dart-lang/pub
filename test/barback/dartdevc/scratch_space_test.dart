// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:barback/barback.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:pub/src/barback/dartdevc/scratch_space.dart';
import 'package:pub/src/io.dart';

void main() {
  test('Can create and delete a scratch space', () async {
    Map<AssetId, List<int>> allAssets = [
      'dep|lib/dep.dart',
      'myapp|lib/myapp.dart',
      'myapp|web/main.dart',
    ].fold({}, (assets, serializedId) {
      assets[new AssetId.parse(serializedId)] = serializedId.codeUnits;
      return assets;
    });

    var scratchSpace =
        new ScratchSpace((id) => new Stream.fromIterable([allAssets[id]]));
    await scratchSpace.ensureAssets(allAssets.keys);

    expect(p.isWithin(Directory.systemTemp.path, scratchSpace.tempDir.path),
        isTrue);

    for (var id in allAssets.keys) {
      var file = scratchSpace.fileFor(id);
      expect(file.existsSync(), isTrue);
      expect(file.readAsStringSync(), equals('$id'));

      var relativeFilePath =
          p.relative(file.path, from: scratchSpace.tempDir.path);
      if (topLevelDir(id.path) == 'lib') {
        var packagesPath =
            p.join('packages', id.package, p.relative(id.path, from: 'lib'));
        expect(relativeFilePath, equals(packagesPath));
      } else {
        expect(relativeFilePath, equals(id.path));
      }
    }

    await scratchSpace.delete();

    for (var id in allAssets.keys) {
      var file = scratchSpace.fileFor(id);
      expect(file.existsSync(), isFalse);
    }
    expect(scratchSpace.tempDir.existsSync(), isFalse);
  });

  test('canonicalUriFor', () {
    expect(canonicalUriFor(new AssetId('a', 'lib/a.dart')),
        equals('package:a/a.dart'));
    expect(canonicalUriFor(new AssetId('a', 'lib/src/a.dart')),
        equals('package:a/src/a.dart'));
    expect(
        canonicalUriFor(new AssetId('a', 'web/a.dart')), equals('web/a.dart'));

    expect(
        () => canonicalUriFor(new AssetId('a', 'a.dart')), throwsArgumentError);
    expect(() => canonicalUriFor(new AssetId('a', 'lib/../a.dart')),
        throwsArgumentError);
    expect(() => canonicalUriFor(new AssetId('a', 'web/../a.dart')),
        throwsArgumentError);
  });
}
