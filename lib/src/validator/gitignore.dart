// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../git.dart' as git;
import '../ignore.dart';
import '../io.dart';
import '../log.dart' as log;
import '../utils.dart';
import '../validator.dart';

/// A validator that validates that no checked in files are ignored by a
/// .gitignore. These would be considered part of the package by previous
/// versions of pub.
class GitignoreValidator extends Validator {
  @override
  Future<void> validate() async {
    if (entrypoint.root.inGitRepo) {
      late final List<String> checkedIntoGit;
      try {
        checkedIntoGit = git.runSync(
          [
            'ls-files',
            '--cached',
            '--exclude-standard',
            '--recurse-submodules'
          ],
          workingDir: entrypoint.rootDir,
        );
      } on git.GitException catch (e) {
        log.fine('Could not run `git ls-files` files in repo (${e.message}).');
        // This validation is only a warning.
        // If git is not supported on the platform, or too old to support
        // --recurse-submodules we just continue silently.
        return;
      }
      final root = git.repoRoot(entrypoint.rootDir) ?? entrypoint.rootDir;
      var beneath = p.posix.joinAll(
        p.split(p.normalize(p.relative(entrypoint.rootDir, from: root))),
      );
      if (beneath == './') {
        beneath = '';
      }
      String resolve(String path) {
        if (Platform.isWindows) {
          return p.joinAll([root, ...p.posix.split(path)]);
        }
        return p.join(root, path);
      }

      final unignoredByGitignore = Ignore.listFiles(
        beneath: beneath,
        listDir: (dir) {
          var contents = Directory(resolve(dir)).listSync();
          return contents
              .where((e) => !(linkExists(e.path) && dirExists(e.path)))
              .map(
                (entity) => p.posix
                    .joinAll(p.split(p.relative(entity.path, from: root))),
              );
        },
        ignoreForDir: (dir) {
          final gitIgnore = resolve('$dir/.gitignore');
          final rules = [
            if (fileExists(gitIgnore)) readTextFile(gitIgnore),
          ];
          return rules.isEmpty ? null : Ignore(rules);
        },
        isDir: (dir) => dirExists(resolve(dir)),
      ).map((file) {
        final relative = p.relative(resolve(file), from: entrypoint.rootDir);
        return Platform.isWindows
            ? p.posix.joinAll(p.split(relative))
            : relative;
      }).toSet();
      final ignoredFilesCheckedIn = checkedIntoGit
          .where((file) => !unignoredByGitignore.contains(file))
          .toList();

      if (ignoredFilesCheckedIn.isNotEmpty) {
        warnings.add('''
${ignoredFilesCheckedIn.length} checked-in ${pluralize('file', ignoredFilesCheckedIn.length)} ${ignoredFilesCheckedIn.length == 1 ? 'is' : 'are'} ignored by a `.gitignore`.
Previous versions of Pub would include those in the published package.

Consider adjusting your `.gitignore` files to not ignore those files, and if you do not wish to
publish these files use `.pubignore`. See also dart.dev/go/pubignore

Files that are checked in while gitignored:

${ignoredFilesCheckedIn.take(10).join('\n')}
${ignoredFilesCheckedIn.length > 10 ? '...' : ''}
''');
      }
    }
  }
}
