// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

@TestOn('linux')
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' show sandbox;
import 'package:path/path.dart' as p;
import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:pub/src/io.dart' show runProcess;

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

const pubspec = 'name: foo\r\ndescription: test\r\nversion: 3.0.0';
const gitattributes = 'foo.dylib filter=lfs diff=lfs merge=lfs -text';

String fakeGit(hash, lfs) {
  return '''
#!/bin/bash -e
case \$@ in
  --version)
    echo 'git version 2.16'
    ;;
  rev-list*)
    echo '$hash'
    ;;
  show*)
    echo '$pubspec'
    ;;
  checkout*)
    mkdir -p $sandbox/cache/git/foo-$hash/.git
    echo '$pubspec' > $sandbox/cache/git/foo-$hash/pubspec.yaml
    echo '$gitattributes' > $sandbox/cache/git/foo-$hash/.gitattributes
    ;;
  $lfs
esac
''';
}

void main() {
  test('reports failure if Git LFS is needed but is not installed', () async {
    ensureGit();

    final repo = d.git('foo.git', [
      d.libDir('foo'),
      d.file('pubspec.yaml', pubspec),
      d.file('.gitattributes', gitattributes)
    ]);

    await repo.create();
    final ref = await repo.runGit(['rev-list', '--max-count=1', 'HEAD']);
    final hash = ref.first;

    await d.appDir({
      'foo': {
        'git': {'url': '../foo.git'}
      }
    }).create();

    const lfs = '''
  lfs*)
    echo "git: 'lfs' is not a git command. See 'git --help'."
    exit 1
    ;;
  ''';

    await d.dir('bin', [d.file('git', fakeGit(hash, lfs))]).create();
    final binFolder = p.join(sandbox, 'bin');
    // chmod the git script
    if (!Platform.isWindows) {
      await runProcess('chmod', ['+x', p.join(sandbox, 'bin', 'git')]);
    }

    final separator = Platform.isWindows ? ';' : ':';

    await runPub(
        args: ['get'],
        error: contains('git lfs not found'),
        environment: {
          // Override 'PATH' to ensure that we are using our fake git executable
          'PATH': '$binFolder$separator${Platform.environment['PATH']}'
        });
  });

  test('reports success if Git proceeds as usual due to no .gitattributes',
      () async {
    ensureGit();

    await d.git('foo.git', [
      d.libDir('foo'),
      d.libPubspec('foo', '3.0.0'),
    ]).create();

    await d.appDir({
      'foo': {
        'git': {'url': '../foo.git'}
      }
    }).create();

    await runPub(args: ['get'], output: contains('Changed 1 dependency!'));
  });

  test('if Git LFS is installed then `git lfs pull` is executed', () async {
    ensureGit();

    final repo = d.git('foo.git', [
      d.libDir('foo'),
      d.file('pubspec.yaml', pubspec),
      d.file('.gitattributes', gitattributes)
    ]);

    await repo.create();
    final ref = await repo.runGit(['rev-list', '--max-count=1', 'HEAD']);
    final hash = ref.first;

    await d.appDir({
      'foo': {
        'git': {'url': '../foo.git'}
      }
    }).create();

    const lfs = '''
  'lfs install'*)
    echo 'git lfs install'
    ;;
  'lfs pull')
    echo 'git lfs pull was reached'
    exit 1
    ;;
  ''';

    await d.dir('bin', [d.file('git', fakeGit(hash, lfs))]).create();
    final binFolder = p.join(sandbox, 'bin');
    // chmod the git script
    if (!Platform.isWindows) {
      await runProcess('chmod', ['+x', p.join(sandbox, 'bin', 'git')]);
    }

    final separator = Platform.isWindows ? ';' : ':';

    await runPub(
        args: ['get'],
        error: contains('git lfs pull was reached'),
        environment: {
          // Override 'PATH' to ensure that we are using our fake git executable
          'PATH': '$binFolder$separator${Platform.environment['PATH']}'
        },
        exitCode: exit_codes.UNAVAILABLE);
  });
}
