// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Helper functionality for invoking Git.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:pub_semver/pub_semver.dart';

import 'command_runner.dart';
import 'exceptions.dart';
import 'io.dart';
import 'log.dart' as log;
import 'path.dart';
import 'utils.dart';

/// An exception thrown because a git command failed.
class GitException implements ApplicationException {
  /// The arguments to the git command.
  final List<String> args;

  /// The standard error emitted by git.
  final dynamic stderr;

  /// The standard out emitted by git.
  final dynamic stdout;

  /// The error code
  final int exitCode;

  @override
  String get message =>
      'Git error. Command: `git ${args.join(' ')}`\n'
      'stdout: ${stdout is String ? stdout : '<binary>'}\n'
      'stderr: ${stderr is String ? stderr : '<binary>'}\n'
      'exit code: $exitCode';

  GitException(Iterable<String> args, this.stdout, this.stderr, this.exitCode)
    : args = args.toList();

  @override
  String toString() => message;
}

/// Tests whether or not the git command-line app is available for use.
bool get isInstalled => command != null;

/// Splits the [output] of a git -z command at \0.
///
/// The first [skipPrefix] bytes of each substring will be ignored (useful for
/// `git status -z`). If there are not enough bytes to skip, throws a
/// [FormatException].
List<Uint8List> splitZeroTerminated(Uint8List output, {int skipPrefix = 0}) {
  final result = <Uint8List>[];
  var start = 0;

  for (var i = 0; i < output.length; i++) {
    if (output[i] != 0) {
      continue;
    }
    if (start + skipPrefix > i) {
      throw FormatException('Substring too short for prefix at $start');
    }
    result.add(
      Uint8List.sublistView(
        output,
        // The first 3 bytes are the modification status.
        // Skip those.
        start + skipPrefix,
        i,
      ),
    );

    start = i + 1;
  }
  return result;
}

/// Run a git process with [args] from [workingDir].
///
/// Returns the stdout if it succeeded. Completes to ans exception if it failed.
Future<String> run(
  List<String> args, {
  String? workingDir,
  Map<String, String>? environment,
  Encoding stdoutEncoding = systemEncoding,
  Encoding stderrEncoding = systemEncoding,
}) async {
  if (!isInstalled) {
    fail(
      'Cannot find a Git executable.\n'
      'Please ensure Git is correctly installed.',
    );
  }

  log.muteProgress();
  try {
    final result = await runProcess(
      command!,
      args,
      workingDir: workingDir,
      environment: {...?environment, 'LANG': 'en_GB'},
      stdoutEncoding: stdoutEncoding,
      stderrEncoding: stderrEncoding,
    );
    if (!result.success) {
      throw GitException(args, result.stdout, result.stderr, result.exitCode);
    }
    return result.stdout;
  } finally {
    log.unmuteProgress();
  }
}

/// Like [run], but synchronous.
String runSync(
  List<String> args, {
  String? workingDir,
  Map<String, String>? environment,
  Encoding stdoutEncoding = systemEncoding,
  Encoding stderrEncoding = systemEncoding,
}) {
  if (!isInstalled) {
    fail(
      'Cannot find a Git executable.\n'
      'Please ensure Git is correctly installed.',
    );
  }

  final result = runProcessSync(
    command!,
    args,
    workingDir: workingDir,
    environment: environment,
    stdoutEncoding: stdoutEncoding,
    stderrEncoding: stderrEncoding,
  );
  if (!result.success) {
    throw GitException(args, result.stdout, result.stderr, result.exitCode);
  }

  return result.stdout;
}

/// Like [run], but synchronous. Returns raw stdout as `Uint8List`.
Uint8List runSyncBytes(
  List<String> args, {
  String? workingDir,
  Map<String, String>? environment,
  Encoding stderrEncoding = systemEncoding,
}) {
  if (!isInstalled) {
    fail(
      'Cannot find a Git executable.\n'
      'Please ensure Git is correctly installed.',
    );
  }

  final result = runProcessSyncBytes(
    command!,
    args,
    workingDir: workingDir,
    environment: environment,
    stderrEncoding: stderrEncoding,
  );
  if (!result.success) {
    throw GitException(args, result.stdout, result.stderr, result.exitCode);
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
        runSync(['rev-parse', '--show-toplevel'], workingDir: dir).trim(),
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
    final result = runProcessSync(command, ['--version']);
    final output = result.stdout;

    // Some users may have configured commands such as autorun, which may
    // produce additional output, so we need to look for "git version"
    // in every line of the output.
    final match = RegExp(
      r'^git version (\d+)\.(\d+)\..*$',
      multiLine: true,
    ).matchAsPrefix(output);
    if (match == null) return false;
    final versionString = match[0]!.substring('git version '.length);
    // Git seems to use many parts in the version number. We just check the
    // first two.
    final major = int.parse(match[1]!);
    final minor = int.parse(match[2]!);
    if (Version(major, minor, 0) < _minSupportedGitVersion) {
      // We just warn here, as some features might work with older versions of
      // git.
      log.warning('''
You have a very old version of git (version $versionString),
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
