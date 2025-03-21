// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../golden_file.dart';
import '../test_pub.dart';
import 'utils.dart';

/// The maximum number of bytes in an entire path.
///
/// This is [Windows's number][MAX_PATH], which is a much tighter constraint
/// than OS X or Linux. We subtract one because Windows counts it as the number
/// of bytes in a path C string including the terminating NUL but we only count
/// characters here.
///
/// We use this limit on all platforms for consistency.
///
/// [MAX_PATH]: https://msdn.microsoft.com/en-us/library/windows/desktop/aa383130(v=vs.85).aspx
const _pathMax = 260 - 1;

void main() {
  testWithGolden('displays all files', (context) async {
    await d.validPackage().create();
    await d.dir(appPath, [
      d.dir('lib', List.generate(20, (i) => d.file('file_$i.dart'))),
    ]).create();
    await servePackages();
    await d.credentialsFile(globalServer, 'access-token').create();
    final pub = await startPublish(globalServer);
    pub.stdin.writeln('y');
    handleUploadForm(globalServer);
    handleUpload(globalServer);

    globalServer.expect('GET', '/create', (request) {
      return shelf.Response.ok(
        jsonEncode({
          'success': {'message': 'Package test_pkg 1.0.0 uploaded!'},
        }),
      );
    });
    await pub.shouldExit(exit_codes.SUCCESS);
    final stdout = await pub.stdout.rest.toList();

    context.expectNextSection(
      stdout.join('\n').replaceAll(globalServer.port.toString(), r'$PORT'),
    );
  });

  test('archives and uploads a package with more files than can fit on '
      'the command line', () async {
    await d.validPackage().create();

    int argMax;
    if (Platform.isWindows) {
      // On Windows, the maximum argument list length is 8^5 bytes.
      argMax = 32768; // 8^5
    } else {
      // On POSIX, the maximum argument list length can be retrieved
      // automatically.
      final result = Process.runSync('getconf', ['ARG_MAX']);
      if (result.exitCode != 0) {
        fail(
          'getconf failed with exit code ${result.exitCode}:\n'
          '${result.stderr}',
        );
      }

      argMax = int.parse(result.stdout as String);
    }

    final appRoot = p.join(d.sandbox, appPath);

    // We'll make the filenames as long as possible to reduce the number of
    // files we have to create to hit the maximum. However, the tar process
    // uses relative paths, which means we can't count the root as part of the
    // length.
    final lengthPerFile = _pathMax - appRoot.length;

    // Create enough files to hit [argMax]. This may be a slight overestimate,
    // since other options are passed to the tar command line, but we don't
    // know how long those will be.
    final filesToCreate = (argMax / lengthPerFile).ceil();

    for (var i = 0; i < filesToCreate; i++) {
      final iString = i.toString();

      // The file name contains "x"s to make the path hit [_pathMax],
      // followed by a number to distinguish different files.
      final fileName =
          'x' * (_pathMax - appRoot.length - iString.length - 1) + iString;

      File(p.join(appRoot, fileName)).writeAsStringSync('');
    }

    await servePackages();
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
}
