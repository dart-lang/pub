// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('linux')
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub/src/io.dart' show runProcess;
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' show sandbox;

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

/// Create temporary folder 'bin/' containing a 'git' script in [sandbox]
/// By adding the bin/ folder to the search `$PATH` we can prevent `pub` from
/// detecting the installed 'git' binary and we can test that it prints
/// a useful error message.
Future<void> setUpFakeGitScript(
    {required String bash, required String batch}) async {
  await d.dir('bin', [
    if (!Platform.isWindows) d.file('git', bash),
    if (Platform.isWindows) d.file('git.bat', batch),
  ]).create();
  if (!Platform.isWindows) {
    // Make the script executable.

    await runProcess('chmod', ['+x', p.join(sandbox, 'bin', 'git')]);
  }
}

/// Returns an environment where PATH is extended with `$sandbox/bin`.
Map<String, String> extendedPathEnv() {
  final separator = Platform.isWindows ? ';' : ':';
  final binFolder = p.join(sandbox, 'bin');

  return {
    // Override 'PATH' to ensure that we can't detect a working "git" binary
    'PATH': '$binFolder$separator${Platform.environment['PATH']}',
  };
}

void main() {
  test('reports failure if Git is not installed', () async {
    await setUpFakeGitScript(bash: '''
#!/bin/bash -e
echo "not git"
exit 1
''', batch: '''
echo "not git"
''');
    await d.appDir({
      'foo': {'git': '../foo.git'}
    }).create();

    await pubGet(
      environment: extendedPathEnv(),
      error: contains('Cannot find a Git executable'),
      exitCode: 1,
    );
  });

  test('warns if git version is too old', () async {
    await setUpFakeGitScript(bash: '''
#!/bin/bash -e
if [ "\$1" == "--version" ]
then
  echo "git version 2.13.1.616"
  exit 1
else
  PATH=${Platform.environment['PATH']} git \$*
fi
''', batch: '''
if "%1"=="--version" (
  echo "git version 2.13.1.616"
) else (
  set path="${Platform.environment['PATH']}"
  git %*
)
''');

    await d.git('foo.git', [d.libPubspec('foo', '1.0.0')]).create();

    await d.appDir({
      'foo': {'git': '../foo.git'}
    }).create();

    await pubGet(
      environment: extendedPathEnv(),
      warning:
          contains('You have a very old version of git (version 2.13.1.616)'),
      exitCode: 0,
    );
  });
}
