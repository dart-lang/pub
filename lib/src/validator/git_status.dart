// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../git.dart' as git;
import '../log.dart' as log;
import '../utils.dart';
import '../validator.dart';

/// A validator that validates that no checked in files are modified in git.
///
/// Doesn't report on newly added files, as generated files might not be checked
/// in to git.
class GitStatusValidator extends Validator {
  @override
  Future<void> validate() async {
    if (!package.inGitRepo) {
      return;
    }
    final Uint8List output;
    final String reporoot;
    try {
      final maybeReporoot = git.repoRoot(package.dir);
      if (maybeReporoot == null) {
        log.fine(
          'Could not determine the repository root from ${package.dir}.',
        );
        // This validation is only a warning.
        return;
      }
      reporoot = maybeReporoot;
      output = git.runSyncBytes([
        'status',
        '-z', // Machine parsable
        '--no-renames', // We don't care about renames.

        '--untracked-files=no', // Don't show untracked files.
      ], workingDir: package.dir);
    } on git.GitException catch (e) {
      log.fine('Could not run `git status` files in repo (${e.message}).');
      // This validation is only a warning.
      // If git is not supported on the platform, we just continue silently.
      return;
    }
    final List<String> modifiedFiles;
    try {
      modifiedFiles =
          git
              .splitZeroTerminated(output, skipPrefix: 3)
              .map((bytes) {
                try {
                  final filename = utf8.decode(bytes);
                  final fullPath = p.join(reporoot, filename);
                  if (!files.any((f) => p.equals(fullPath, f))) {
                    // File is not in the published set - ignore.
                    return null;
                  }
                  return p.relative(fullPath);
                } on FormatException catch (e) {
                  // Filename is not utf8 - ignore.
                  log.fine('Cannot decode file name: $e');
                  return null;
                }
              })
              .nonNulls
              .toList();
    } on FormatException catch (e) {
      // Malformed output from `git status`. Skip this validation.
      log.fine('Malformed output from `git status -z`: $e');
      return;
    }
    if (modifiedFiles.isNotEmpty) {
      warnings.add('''
${modifiedFiles.length} checked-in ${pluralize('file', modifiedFiles.length)} ${modifiedFiles.length == 1 ? 'is' : 'are'} modified in git.

Usually you want to publish from a clean git state.

Consider committing these files or reverting the changes.

Modified files:

${modifiedFiles.take(10).map(p.relative).join('\n')}
${modifiedFiles.length > 10 ? '...\n' : ''}
Run `git status` for more information.
''');
    }
  }
}
