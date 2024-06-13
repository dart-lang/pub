// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:shelf/shelf.dart' as shelf;
import 'package:tar/tar.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

/// The assumed default file mode on Linux and macOS
const _defaultMode = 420; // 644₈

/// Mask for executable bits in file modes.
const _executableMask = 0x49; // 001 001 001

void main() {
  test(
      'archives and uploads empty directories in package. Maintains the executable bit',
      () async {
    await d.validPackage().create();
    await d.dir(appPath, [
      d.dir('tool', [d.file('tool.sh', 'commands...')]),
      d.dir('lib', [d.dir('empty')]),
    ]).create();

    if (!Platform.isWindows) {
      Process.runSync(
        'chmod',
        ['+x', p.join(d.sandbox, appPath, 'tool', 'tool.sh')],
      );
    }

    await servePackages();
    await runPub(
      args: ['publish', '--to-archive=archive.tar.gz'],
      output: contains('''
├── CHANGELOG.md (<1 KB)
├── LICENSE (<1 KB)
├── README.md (<1 KB)
├── lib
│   ├── empty
│   └── test_pkg.dart (<1 KB)
├── pubspec.yaml (<1 KB)
└── tool
    └── tool.sh (<1 KB)
'''),
    );
    expect(
      File(p.join(d.sandbox, appPath, 'archive.tar.gz')).existsSync(),
      isTrue,
    );
    final tarReader = TarReader(
      gzip.decoder.bind(
        File(p.join(d.sandbox, appPath, 'archive.tar.gz')).openRead(),
      ),
    );
    final dirs = <String>[];
    while (await tarReader.moveNext()) {
      final entry = tarReader.current;
      if (entry.type == TypeFlag.dir) {
        if (!Platform.isWindows) {
          expect(entry.header.mode, _defaultMode | _executableMask);
        }
        dirs.add(entry.name);
      } else {
        if (!Platform.isWindows) {
          if (entry.name.endsWith('tool.sh')) {
            expect(
              entry.header.mode
                  // chmod +x doesn't sets the executable bit for other users on some platforms only.
                  |
                  1,
              _defaultMode | _executableMask,
            );
          } else {
            expect(entry.header.mode, _defaultMode);
          }
        }
      }
    }
    expect(dirs, ['tool', 'lib', 'lib/empty']);
    await d.credentialsFile(globalServer, 'access-token').create();
    final pub = await startPublish(globalServer);

    await confirmPublish(pub);
    handleUploadForm(globalServer);
    handleUpload(globalServer);

    globalServer.expect('GET', '/create', (request) {
      return shelf.Response.ok(
        jsonEncode({
          'success': {'message': 'Package test_pkg 1.0.0 uploaded!'},
        }),
      );
    });

    expect(pub.stdout, emits(startsWith('Uploading...')));
    expect(
      pub.stdout,
      emits('Message from server: Package test_pkg 1.0.0 uploaded!'),
    );
    await pub.shouldExit(exit_codes.SUCCESS);
  });

  test('Can download and unpack package with empty directory', () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      contents: [
        d.dir('lib', [d.dir('empty', [])]),
      ],
    );
    await d.appDir(dependencies: {'foo': '1.0.0'}).create();
    await pubGet();
    await d.hostedCache([
      d.dir('foo-1.0.0', [
        d.dir('lib', [d.dir('empty')]),
      ]),
    ]).validate();
  });
}
