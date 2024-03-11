// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';
import 'package:yaml_edit/yaml_edit.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test("fails if the current SDK doesn't match the constraint", () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      contents: [
        d.dir('bin', [d.file('script.dart', "main(args) => print('ok');")]),
      ],
      sdk: '3.1.2+3',
    );

    await runPub(args: ['global', 'activate', 'foo']);

    await runPub(
      args: ['global', 'run', 'foo:script'],
      error:
          contains("foo as globally activated doesn't support Dart 3.1.2+4."),
      exitCode: exit_codes.DATA,
      environment: {'_PUB_TEST_SDK_VERSION': '3.1.2+4'},
    );
  });

  test('fails if SDK is downgraded below the constraints', () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      sdk: '^3.0.1',
      contents: [
        d.dir('bin', [d.file('script.dart', "main(args) => print('123-OK');")]),
      ],
    );

    await runPub(args: ['global', 'activate', 'foo']);

    await runPub(
      args: ['global', 'run', 'foo:script'],
      output: contains('123-OK'),
    );

    await runPub(
      environment: {
        // Not compatible with [defaultSdkConstraint].
        '_PUB_TEST_SDK_VERSION': '3.0.0',
      },
      args: ['global', 'run', 'foo:script'],
      error: contains("foo as globally activated doesn't support Dart 3.0.0."),
      exitCode: exit_codes.DATA,
    );
  });

  test('fails if SDK is downgraded below dependency SDK constraints', () async {
    await servePackages()
      ..serve(
        'foo',
        '1.0.0',
        deps: {
          'bar': '^1.0.0',
        },
        sdk: '^3.0.0',
        contents: [
          d.dir(
            'bin',
            [d.file('script.dart', "main(args) => print('123-OK');")],
          ),
        ],
      )
      ..serve(
        'bar',
        '1.0.0',
        pubspec: {
          'environment': {
            'sdk': '^3.0.1',
          },
        },
      );

    await runPub(args: ['global', 'activate', 'foo']);

    await runPub(
      args: ['global', 'run', 'foo:script'],
      output: contains('123-OK'),
    );

    await runPub(
      environment: {'_PUB_TEST_SDK_VERSION': '3.0.0'},
      args: ['global', 'run', 'foo:script'],
      error: contains(
        """
foo as globally activated doesn't support Dart 3.0.0.

try:
`dart pub global activate foo` to reactivate.""",
      ),
      exitCode: exit_codes.DATA,
    );
  });

  test('succeeds if SDK is upgraded from 2.19 to 3.0', () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      sdk: '^2.19.0',
      contents: [
        d.dir(
          'bin',
          [d.file('script.dart', "main(args) => print('123-OK');")],
        ),
      ],
    );

    await runPub(
      environment: {'_PUB_TEST_SDK_VERSION': '2.19.0'},
      args: ['global', 'activate', 'foo'],
    );

    final lockFile = File(
      p.join(d.sandbox, cachePath, 'global_packages', 'foo', 'pubspec.lock'),
    );
    final editor = YamlEditor(lockFile.readAsStringSync());
    // This corresponds to what an older sdk would write, before the dart 3 hack
    // was introduced:
    editor.update(['sdks', 'dart'], '^2.19.0');

    await runPub(
      environment: {'_PUB_TEST_SDK_VERSION': '3.0.0'},
      args: ['global', 'run', 'foo:script'],
      output: contains('123-OK'),
    );
  });
}
