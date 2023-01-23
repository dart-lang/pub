// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('linux')
import 'dart:io';

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('reports failure if Git is not installed', () async {
    await setUpFakeGitScript(
      bash: '''
#!/bin/bash -e
echo "not git"
exit 1
''',
      batch: '''
echo "not git"
''',
    );
    await d.appDir(
      dependencies: {
        'foo': {'git': '../foo.git'}
      },
    ).create();

    await pubGet(
      environment: extendedPathEnv(),
      error: contains('Cannot find a Git executable'),
      exitCode: 1,
    );
  });

  test('warns if git version is too old', () async {
    await setUpFakeGitScript(
      bash: '''
#!/bin/bash -e
if [ "\$1" == "--version" ]
then
  echo "git version 2.13.1.616"
  exit 1
else
  PATH=${Platform.environment['PATH']} git \$*
fi
''',
      batch: '''
if "%1"=="--version" (
  echo "git version 2.13.1.616"
) else (
  set path="${Platform.environment['PATH']}"
  git %*
)
''',
    );

    await d.git('foo.git', [d.libPubspec('foo', '1.0.0')]).create();

    await d.appDir(
      dependencies: {
        'foo': {'git': '../foo.git'}
      },
    ).create();

    await pubGet(
      environment: extendedPathEnv(),
      warning:
          contains('You have a very old version of git (version 2.13.1.616)'),
      exitCode: 0,
    );
  });
}
