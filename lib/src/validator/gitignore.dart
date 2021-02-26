// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub/src/utils.dart';
import '../entrypoint.dart';
import '../git.dart' as git;
import '../ignore.dart';
import '../validator.dart';

/// A validator that validates that no checked in files are ignored by a
/// .gitignore. These would be considered part of the package by previous
/// versions of pub.
class GitignoreValidator extends Validator {
  GitignoreValidator(Entrypoint entrypoint) : super(entrypoint);

  @override
  Future<void> validate() async {
    if (entrypoint.root.inGitRepo) {
      final checkedIntoGit = git.runSync(
          ['ls-files', '--cached', '--exclude-standard'],
          workingDir: entrypoint.root.dir);
      final problems = <String>[];
      for (final f in checkedIntoGit) {
        final directoryUri = Directory('${entrypoint.root.dir}/').uri;
        final isIgnored = Ignore.unignoredFiles(
                beneath: f,
                listDir: (dir) {
                  final startOfNext = dir.isEmpty ? 0 : dir.length + 1;
                  final nextSlash = f.indexOf('/', startOfNext);
                  return [f.substring(startOfNext, nextSlash)];
                },
                ignoresForDir: (dir) {
                  final gitIgnore = File.fromUri(directoryUri
                      .resolve('${dir == '' ? '.' : dir}/.gitignore'));
                  return gitIgnore.existsSync()
                      ? Ignore([gitIgnore.readAsStringSync()])
                      : null;
                },
                isDir: (candidate) =>
                    f.length > candidate.length && f[candidate.length] == '/')
            .map((e) => directoryUri.resolve(e).path)
            .isEmpty;
        if (isIgnored) {
          problems.add(f);
        }
      }
      if (problems.isNotEmpty) {
        warnings.add('''
${problems.length} checked in ${pluralize('files', problems.length)} are ignored by a `.gitignore`.
Previous versions of Pub would include those in the published package.

Consider adjusting your .gitignore files to not ignore those files.

Here are some files:

${problems.take(10).join('\n')}
''');
      }
    }
  }
}
