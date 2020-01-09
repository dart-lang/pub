// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Helper functionality for invoking Git.
import 'dart:async';
import 'dart:io';

import 'package:stack_trace/stack_trace.dart';

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
    {String workingDir, Map<String, String> environment}) async {
  if (!isInstalled) {
    fail('Cannot find a Git executable.\n'
        'Please ensure Git is correctly installed.');
  }

  log.muteProgress();
  try {
    var result = await runProcess(command, args,
        workingDir: workingDir, environment: environment);
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
    {String workingDir, Map<String, String> environment}) {
  if (!isInstalled) {
    fail('Cannot find a Git executable.\n'
        'Please ensure Git is correctly installed.');
  }

  var result = runProcessSync(command, args,
      workingDir: workingDir, environment: environment);
  if (!result.success) {
    throw GitException(args, result.stdout.join('\n'), result.stderr.join('\n'),
        result.exitCode);
  }

  return result.stdout;
}

/// Returns the name of the git command-line app, or `null` if Git could not be
/// found on the user's PATH.
String get command {
  if (_commandCache != null) return _commandCache;

  if (_tryGitCommand('git')) {
    _commandCache = 'git';
  } else if (_tryGitCommand('git.cmd')) {
    _commandCache = 'git.cmd';
  } else {
    return null;
  }

  log.fine('Determined git command $_commandCache.');
  return _commandCache;
}

String _commandCache;

/// Checks whether [command] is the Git command for this computer.
bool _tryGitCommand(String command) {
  // If "git --version" prints something familiar, git is working.
  try {
    var result = runProcessSync(command, ['--version']);
    var regexp = RegExp('^git version');
    return result.stdout.length == 1 && regexp.hasMatch(result.stdout.single);
  } on ProcessException catch (error, stackTrace) {
    var chain = Chain.forTrace(stackTrace);
    // If the process failed, they probably don't have it.
    log.error('Git command is not "$command": $error\n$chain');
    return false;
  }
}
