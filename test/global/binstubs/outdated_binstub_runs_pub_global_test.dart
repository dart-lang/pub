// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test_process/test_process.dart';
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';
import 'utils.dart';

/// The contents of the binstub for [executable], or `null` if it doesn't exist.
String binStub(String executable) {
  final f = File(p.join(d.sandbox, cachePath, 'bin', binStubName(executable)));
  if (f.existsSync()) {
    return f.readAsStringSync();
  }
  return null;
}

void main() {
  test("an outdated binstub runs 'pub global run', which replaces old binstub",
      () async {
    await servePackages((builder) {
      builder.serve('foo', '1.0.0', pubspec: {
        'executables': {
          'foo-script': 'script',
          'foo-script2': 'script',
          'foo-script-not-installed': 'script',
          'foo-another-script': 'another-script',
          'foo-another-script-not-installed': 'another-script'
        }
      }, contents: [
        d.dir('bin', [
          d.file('script.dart', r"main(args) => print('ok $args');"),
          d.file('another-script.dart',
              r"main(args) => print('not so good $args');")
        ])
      ]);
    });

    await runPub(args: [
      'global',
      'activate',
      'foo',
      '--executable',
      'foo-script',
      '--executable',
      'foo-script2',
      '--executable',
      'foo-another-script',
    ], environment: {
      '_PUB_TEST_SDK_VERSION': '0.0.1'
    });

    expect(binStub('foo-script'), contains('script.dart-0.0.1.snapshot'));

    expect(binStub('foo-script2'), contains('script.dart-0.0.1.snapshot'));

    expect(
      binStub('foo-script-not-installed'),
      null,
    );

    expect(
      binStub('foo-another-script'),
      contains('another-script.dart-0.0.1.snapshot'),
    );

    expect(
      binStub('foo-another-script-not-installed'),
      null,
    );

    // Replace the created snapshot with one that really doesn't work with the
    // current dart.
    await d.dir(cachePath, [
      d.dir('global_packages', [
        d.dir('foo', [
          d.dir(
            'bin',
            [d.outOfDateSnapshot('script.dart-0.0.1.snapshot')],
          )
        ])
      ])
    ]).create();

    var process = await TestProcess.start(
        p.join(d.sandbox, cachePath, 'bin', binStubName('foo-script')),
        ['arg1', 'arg2'],
        environment: getEnvironment());

    expect(await process.stdout.rest.toList(), contains('ok [arg1, arg2]'));

    expect(
      binStub('foo-script'),
      contains('script.dart-0.1.2+3.snapshot'),
    );

    expect(
      binStub('foo-script2'),
      contains('script.dart-0.1.2+3.snapshot'),
    );

    expect(
      binStub('foo-script-not-installed'),
      null,
      reason: 'global run recompile should not install new binstubs',
    );

    expect(
      binStub('foo-another-script'),
      contains('another-script.dart-0.0.1.snapshot'),
      reason:
          'global run recompile should not refresh binstubs for other scripts',
    );

    expect(
      binStub('foo-another-script-not-installed'),
      null,
      reason:
          'global run recompile should not install binstubs for other scripts',
    );

    await process.shouldExit();
  });
}
