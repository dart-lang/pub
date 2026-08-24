// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:pub/src/io.dart';
import 'package:pub/src/path.dart';
import 'package:tar/tar.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

const _defaultMode = 420; // 644₈
const _executableMask = 0x49; // 001 001 001

void main() {
  test('creates byte-for-byte identical archives regardless '
      'of file mtime or creation order', () async {
    await d.validPackage().create();
    await d.dir(appPath, [
      d.dir('lib', [
        d.file('z.dart', 'void z() {}'),
        d.file('a.dart', 'void a() {}'),
        d.file('m.dart', 'void m() {}'),
      ]),
      d.dir('bin', [d.file('tool.dart', 'void main() {}')]),
    ]).create();

    // Generate first archive
    await runPub(args: ['publish', '--to-archive=../archive1.tar.gz']);

    final archive1File = File(p.join(d.sandbox, 'archive1.tar.gz'));
    expect(archive1File.existsSync(), isTrue);
    final bytes1 = archive1File.readAsBytesSync();
    final digest1 = sha256.convert(bytes1).toString();

    // Alter file timestamps on disk
    final aFile = File(p.join(d.sandbox, appPath, 'lib', 'a.dart'));
    final zFile = File(p.join(d.sandbox, appPath, 'lib', 'z.dart'));
    aFile.setLastModifiedSync(DateTime(2030, 5, 12, 10, 30));
    zFile.setLastModifiedSync(DateTime(1995, 3, 4, 12));

    // Wait a brief moment and generate second archive
    await runPub(args: ['publish', '--to-archive=../archive2.tar.gz']);

    final archive2File = File(p.join(d.sandbox, 'archive2.tar.gz'));
    expect(archive2File.existsSync(), isTrue);
    final bytes2 = archive2File.readAsBytesSync();
    final digest2 = sha256.convert(bytes2).toString();

    // Digests must match identically
    expect(digest2, equals(digest1));
    expect(bytes2, equals(bytes1));

    // Inspect TAR entries
    final tarReader = TarReader(gzip.decoder.bind(archive1File.openRead()));
    final entryNames = <String>[];
    while (await tarReader.moveNext()) {
      final entry = tarReader.current;
      entryNames.add(entry.name);
      // Verify normalized epoch timestamp
      expect(
        entry.header.modified,
        equals(DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)),
      );
      expect(entry.header.userName, equals('pub'));
      expect(entry.header.groupName, equals('pub'));
      if (entry.type == TypeFlag.dir) {
        if (!Platform.isWindows) {
          expect(entry.header.mode, equals(_defaultMode | _executableMask));
        }
      } else {
        if (!Platform.isWindows) {
          expect(entry.header.mode, equals(_defaultMode));
        }
      }
    }

    // Verify entries are sorted deterministically
    final sortedNames = List<String>.from(entryNames)..sort();
    expect(entryNames, equals(sortedNames));
  });

  test('respects ${EnvironmentKeys.sourceDateEpoch} environment variable for '
      'archive entries', () async {
    await d.validPackage().create();
    await d.dir(appPath, [
      d.dir('lib', [d.file('lib.dart', 'void foo() {}')]),
    ]).create();

    const customEpochSeconds = 1700000000;
    final expectedDate = DateTime.fromMillisecondsSinceEpoch(
      customEpochSeconds * 1000,
      isUtc: true,
    );

    await runPub(
      args: ['publish', '--to-archive=../archive_epoch.tar.gz'],
      environment: {EnvironmentKeys.sourceDateEpoch: '$customEpochSeconds'},
    );

    final archiveFile = File(p.join(d.sandbox, 'archive_epoch.tar.gz'));
    final tarReader = TarReader(gzip.decoder.bind(archiveFile.openRead()));

    while (await tarReader.moveNext()) {
      final entry = tarReader.current;
      expect(entry.header.modified, equals(expectedDate));
    }
  });
}
