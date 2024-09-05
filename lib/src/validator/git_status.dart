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

/// A validator that validates that no checked in files are modiofied in git.
///
/// Doesn't report on newly added files, as generated files might not be checked
/// in to git.
class GitStatusValidator extends Validator {
  @override
  Future<void> validate() async {
    if (package.inGitRepo) {
      final modfiedFiles = <String>[];
      try {
        final reporoot = git.repoRoot(package.dir);
        if (reporoot == null) {
          log.fine(
            'Could not determine the repository root from ${package.dir}.',
          );
          // This validation is only a warning.
          return;
        }
        final output = git.runSyncBytes(
          [
            'status',
            '-z', // Machine parsable
            '--no-renames', // We don't care about renames.

            '--untracked-files=no', // Don't show untracked files.
          ],
          workingDir: package.dir,
        );
        // Split at \0.
        var start = 0;
        for (var i = 0; i < output.length; i++) {
          if (output[i] != 0) {
            continue;
          }
          final filename = utf8.decode(
            Uint8List.sublistView(
              output,
              // The first 3 bytes are the modification status.
              // Skip those.
              start + 3,
              i,
            ),
          );
          final fullPath = p.join(reporoot, filename);
          if (!files.any((f) => p.equals(fullPath, f))) {
            // File is not in the published set - ignore.
            continue;
          }
          modfiedFiles.add(p.relative(fullPath));
          start = i + 1;
        }
      } on git.GitException catch (e) {
        log.fine('Could not run `git status` files in repo (${e.message}).');
        // This validation is only a warning.
        // If git is not supported on the platform, we just continue silently.
        return;
      }

      if (modfiedFiles.isNotEmpty) {
        warnings.add('''
${modfiedFiles.length} checked-in ${pluralize('file', modfiedFiles.length)} ${modfiedFiles.length == 1 ? 'is' : 'are'} modified in git.

Usually you want to publish from a clean git state.

Consider committing these files or reverting the changes.

Modified files:

${modfiedFiles.take(10).map(p.relative).join('\n')}
${modfiedFiles.length > 10 ? '...\n' : ''}
Run `git status` for more information.
''');
      }
    }
  }
}
