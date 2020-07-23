// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE d.file.

import 'package:test/test.dart';

import 'package:path/path.dart' as path;
import 'package:pub/src/io.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('prints the local paths to all packages in the lockfile', () async {
    await servePackages((builder) => builder.serve('bar', '1.0.0'));

    await d
        .dir('foo', [d.libDir('foo'), d.libPubspec('foo', '1.0.0')]).create();

    await d.dir(appPath, [
      d.appPubspec({
        'foo': {'path': path.join(d.sandbox, 'foo')},
        'bar': 'any'
      })
    ]).create();

    await pubGet();

    await
        // Note: Using canonicalize here because pub gets the path to the
        // entrypoint package from the working directory, which has had symlinks
        // resolve. On Mac, "/tmp" is actually a symlink to "/private/tmp", so we
        // need to accommodate that.
        await runPub(args: [
      'list-package-dirs',
      '--format=json'
    ], outputJson: {
      'packages': {
        'foo': path.join(d.sandbox, 'foo', 'lib'),
        'bar': path.join(d.sandbox, cachePath, 'hosted',
            'localhost%58${globalServer.port}', 'bar-1.0.0', 'lib'),
        'myapp': canonicalize(path.join(d.sandbox, appPath, 'lib'))
      },
      'input_files': [
        canonicalize(path.join(d.sandbox, appPath, 'pubspec.lock')),
        canonicalize(path.join(d.sandbox, appPath, 'pubspec.yaml'))
      ]
    });
  });
}
