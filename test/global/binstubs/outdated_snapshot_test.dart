// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

import 'package:pub/src/io.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';
import 'utils.dart';

void main() {
  test("a binstub runs 'pub global run' for an outdated snapshot", () async {
    await servePackages((builder) {
      builder.serve('foo', '1.0.0', pubspec: {
        'executables': {'foo-script': 'script'}
      }, contents: [
        d.dir(
            'bin', [d.file('script.dart', "main(args) => print('ok \$args');")])
      ]);
    });

    await runPub(args: ['global', 'activate', 'foo']);

    await d.dir(cachePath, [
      d.dir('global_packages', [
        d.dir('foo', [
          d.dir('bin',
              [d.outOfDateSnapshot('script.dart-$versionSuffix.snapshot-1')])
        ])
      ])
    ]).create();

    deleteEntry(p.join(d.dir(cachePath).io.path, 'global_packages', 'foo',
        'bin', 'script.dart-$versionSuffix.snapshot'));

    var process = await TestProcess.start(
        p.join(d.sandbox, cachePath, 'bin', binStubName('foo-script')),
        ['arg1', 'arg2'],
        environment: getEnvironment());

    // We don't get `Precompiling executable...` because we are running through
    // the binstub.
    expect(process.stdout, emitsThrough('ok [arg1, arg2]'));
    await process.shouldExit();

    // TODO(sigurdm): This is hard to test because the binstub invokes the wrong
    // pub.
    // await d.dir(cachePath, [
    //   d.dir('global_packages/foo/bin', [
    //     d.file(
    //         'script.dart-$versionSuffix.snapshot',
    //         isNot(equals(
    //             readBinaryFile(testAssetPath('out-of-date-$versionSuffix.snapshot')))))
    //   ])
    // ]).validate();
  });
}
