// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Helper functionality for invoking Git.
import 'dart:async';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

import 'command_runner.dart';
import 'exceptions.dart';
import 'io.dart';
import 'log.dart' as log;
import 'utils.dart';

/// An exception thrown because a git command failed.
class GitException implements ApplicationException {
  /// The arguments to the git command.
  final List<String> args;

  /// The standard error emitted by git.
  final String stderr;

  /// The standard out emitted by git.
  final String stdout;

  /// The error code
  final int exitCode;

  @override
  String get message => 'Git error. Command: `git ${args.join(' ')}`\n'
      'stdout: $stdout\n'
      'stderr: $stderr\n'
      'exit code: $exitCode';

  GitException(Iterable<String> args, this.stdout, this.stderr, this.exitCode)
      : args = args.toList();

  @override
  String toString() => message;
}

/// Tests whether or not the git command-line app is available for use.
bool get isInstalled => command != null;

/// Run a git process with [args] from [workingDir].
///
/// Returns the stdout as a list of strings if it succeeded. Completes to an
/// exception if it failed.
Future<List<String>> run(List<String> args,
    {String? workingDir, Map<String, String>? environment}) async {
  if (!isInstalled) {
    fail('Cannot find a Git executable.\n'
        'Please ensure Git is correctly installed.');
  }

  log.muteProgress();
  try {
    final result = await runProcess(command!, args,
        workingDir: workingDir,
        environment: {...?environment, 'LANG': 'en_GB'});
    if (!result.success) {
      throw GitException(args, result.stdout.join('\n'),
          result.stderr.join('\n'), result.exitCode);
    }
    return result.stdout;
  } finally {
    log.unmuteProgress();
  }
}

/// Like [run], but synchronous.
List<String> runSync(List<String> args,
    {String? workingDir, Map<String, String>? environment}) {
  if (!isInstalled) {
    fail('Cannot find a Git executable.\n'
        'Please ensure Git is correctly installed.');
  }

  final result = runProcessSync(command!, args,
      workingDir: workingDir, environment: environment);
  if (!result.success) {
    throw GitException(args, result.stdout.join('\n'), result.stderr.join('\n'),
        result.exitCode);
  }

  return result.stdout;
}

/// The name of the git command-line app, or `null` if Git could not be found on
/// the user's PATH.
final String? command = ['git', 'git.cmd'].firstWhereOrNull(_tryGitCommand);

/// Returns the root of the git repo [dir] belongs to. Returns `null` if not
/// in a git repo or git is not installed.
String? repoRoot(String dir) {
  if (isInstalled) {
    try {
      return p.normalize(
        runSync(['rev-parse', '--show-toplevel'], workingDir: dir).first,
      );
    } on GitException {
      // Not in a git folder.
      return null;
    }
  }
  return null;
}

/// '--recourse-submodules' was introduced in Git 2.14
/// (https://git-scm.com/book/en/v2/Git-Tools-Submodules).
final _minSupportedGitVersion = Version(2, 14, 0);

/// Checks whether [command] is the Git command for this computer.
bool _tryGitCommand(String command) {
  // If "git --version" prints something familiar, git is working.
  try {
    var result = runProcessSync(command, ['--version']);

    if (result.stdout.length != 1) return false;
    final output = result.stdout.single;
    final match = RegExp(r'^git version (\d+)\.(\d+)\.').matchAsPrefix(output);

    if (match == null) return false;
    // Git seems to use many parts in the version number. We just check the
    // first two.
    final major = int.parse(match[1]!);
    final minor = int.parse(match[2]!);
    if (Version(major, minor, 0) < _minSupportedGitVersion) {
      // We just warn here, as some features might work with older versions of
      // git.
      log.warning('''
You have a very old version of git (version ${output.substring('git version '.length)}),
for $topLevelProgram it is recommended to use git version 2.14 or newer.
''');
    }
    log.fine('Determined git command $command.');
    return true;
  } on RunProcessException catch (err) {
    // If the process failed, they probably don't have it.
    log.error('Git command is not "$command": $err');
    return false;
  }
}
