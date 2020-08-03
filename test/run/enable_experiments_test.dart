// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:pub/src/language_version.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test(
    'Succeeds running experimental code.',
    () async {
      await d.dir(appPath, [
        d.appPubspec(),
        d.dir('bin', [
          d.file('script.dart', '''
  main() {
    int? a = int.tryParse('123');
  }
''')
        ])
      ]).create();
      await pubGet();
      await runPub(
          args: ['run', '--enable-experiment=non-nullable', 'bin/script.dart']);
    },
    skip: Platform.version.contains('2.9') || Platform.version.contains('2.10')
        ? false
        : 'experiement non-nullable only available for test on sdk 2.9',
  );

  test(
    'Passes --no-sound-null-safety to the vm',
    () async {
      await d.dir(appPath, [
        d.pubspec({
          'name': 'test_package',
          'environment': {'sdk': '>=2.10.0 <=3.0.0'}
        }),
        d.dir('bin', [
          d.file('script.dart', '''
import 'package:test_package/foo.dart';

main() {
  int? a = int.tryParse('123');
  int b = p;
}
''')
        ]),
        d.dir(
          'lib',
          [
            d.file('foo.dart', '''
// @dart = 2.8
int p = 10;
'''),
          ],
        ),
      ]).create();
      await pubGet(environment: {'_PUB_TEST_SDK_VERSION': '2.10.0'});
      await runPub(args: [
        'run',
        '--no-sound-null-safety',
        '--enable-experiment=non-nullable',
        'bin/script.dart'
      ], environment: {
        '_PUB_TEST_SDK_VERSION': '2.10.0'
      });
      await runPub(
          args: ['run', '--enable-experiment=non-nullable', 'bin/script.dart'],
          environment: {'_PUB_TEST_SDK_VERSION': '2.10.0'},
          error: contains("A library can't opt out of null safety by default"),
          exitCode: 254);
    },
    skip: LanguageVersion.fromVersion(
                Version.parse(Platform.version.split(' ').first)) >=
            LanguageVersion.fromVersion(Version(2, 10, 0))
        ? false
        : '--sound-null-safety only available from sdk 2.10',
  );
}
