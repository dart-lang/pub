// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../entrypoint.dart';
import '../git.dart' as git;
import '../ignore.dart';
import '../utils.dart';
import '../validator.dart';

/// A validator that validates that no checked in files are ignored by a
/// .gitignore. These would be considered part of the package by previous
/// versions of pub.
class GitignoreValidator extends Validator {
  GitignoreValidator(Entrypoint entrypoint) : super(entrypoint);

  @override
  Future<void> validate() async {
    if (entrypoint.root.inGitRepo) {
      final checkedIntoGit = git.runSync([
        'ls-files',
        '--cached',
        '--exclude-standard',
        '--recurse-submodules'
      ], workingDir: entrypoint.root.dir);
      final uri = Directory('${entrypoint.root.dir}/').uri;
      final unignoredByGitignore = Ignore.unignoredFiles(
        listDir: (dir) {
          var contents = Directory.fromUri(uri.resolve(dir)).listSync();
          return contents.map(
              (entity) => p.relative(entity.path, from: entrypoint.root.dir));
        },
        ignoreForDir: (dir) {
          final gitIgnore = File.fromUri(uri.resolve('$dir/.gitignore'));
          final rules = [
            if (gitIgnore.existsSync()) gitIgnore.readAsStringSync(),
          ];
          return rules.isEmpty ? null : Ignore(rules);
        },
        isDir: (dir) => Directory.fromUri(uri.resolve(dir)).existsSync(),
      ).toSet();

      final ignoredFilesCheckedIn = checkedIntoGit
          .where((file) => !unignoredByGitignore.contains(file))
          .toList();

      if (ignoredFilesCheckedIn.isNotEmpty) {
        warnings.add('''
${ignoredFilesCheckedIn.length} checked in ${pluralize('file', ignoredFilesCheckedIn.length)} are ignored by a `.gitignore`.
Previous versions of Pub would include those in the published package.

Consider adjusting your .gitignore files to not ignore those files.

Files that are checked in while gitignored:

${ignoredFilesCheckedIn.take(10).join('\n')}
${ignoredFilesCheckedIn.length > 10 ? '...' : ''}
''');
      }
    }
  }
}
