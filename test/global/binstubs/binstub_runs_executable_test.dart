// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';
import 'utils.dart';

void main() {
  test('the generated binstub runs a snapshotted executable', () async {
    await servePackages((builder) {
      builder.serve('foo', '1.0.0', pubspec: {
        'executables': {'foo-script': 'script'}
      }, contents: [
        d.dir(
            'bin', [d.file('script.dart', "main(args) => print('ok \$args');")])
      ]);
    });

    await runPub(args: ['global', 'activate', 'foo']);

    var process = await TestProcess.start(
        p.join(d.sandbox, cachePath, 'bin', binStubName('foo-script')),
        ['arg1', 'arg2'],
        environment: getEnvironment());

    expect(process.stdout, emits('ok [arg1, arg2]'));
    await process.shouldExit();
  });

  test('the generated binstub runs a non-snapshotted executable', () async {
    await d.dir('foo', [
      d.pubspec({
        'name': 'foo',
        'executables': {'foo-script': 'script'}
      }),
      d.dir('bin', [d.file('script.dart', "main(args) => print('ok \$args');")])
    ]).create();

    await runPub(args: ['global', 'activate', '-spath', '../foo']);

    var process = await TestProcess.start(
        p.join(d.sandbox, cachePath, 'bin', binStubName('foo-script')),
        ['arg1', 'arg2'],
        environment: getEnvironment());

    expect(process.stdout, emits('ok [arg1, arg2]'));
    await process.shouldExit();
  });
}
