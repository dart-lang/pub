// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:args/command_runner.dart';

import 'src/entrypoint.dart';
import 'src/exceptions.dart';
import 'src/http.dart';
import 'src/pub_embeddable_command.dart';
import 'src/source/git.dart';
import 'src/system_cache.dart';

export 'src/executable.dart'
    show
        CommandResolutionFailedException,
        CommandResolutionIssue,
        DartExecutableWithPackageConfig,
        getExecutableForCommand;

/// Returns a [Command] for pub functionality that can be used by an embedding
/// CommandRunner.
///
/// [isVerbose] should return `true` (after argument resolution) if the
/// embedding top-level is in verbose mode.
Command<int> pubCommand({
  required bool Function() isVerbose,
  String category = '',
}) => PubEmbeddableCommand(isVerbose, category);

/// Makes sure that [dir]/pubspec.yaml is resolved such that pubspec.lock and
/// .dart_tool/package_config.json are up-to-date and all packages are
/// downloaded to the cache.
///
/// Will compare file timestamps to see if full resolution can be skipped.
///
/// If [summaryOnly] is `true` (the default) only a short summary is shown of
/// the solve.
///
/// If [onlyOutputWhenTerminal] is `true` (the default) there will be no
/// output if no terminal is attached.
///
/// Throws a [ResolutionFailedException] if resolution fails.
Future<void> ensurePubspecResolved(
  String dir, {
  bool isOffline = false,
  bool summaryOnly = true,
  bool onlyOutputWhenTerminal = true,
}) async {
  try {
    await Entrypoint.ensureUpToDate(
      dir,
      cache: SystemCache(isOffline: isOffline),
      summaryOnly: summaryOnly,
      onlyOutputWhenTerminal: onlyOutputWhenTerminal,
    );
  } on ApplicationException catch (e) {
    throw ResolutionFailedException._(e.toString());
  } finally {
    // TODO(https://github.com/dart-lang/pub/issues/4200)
    // This is a bit of a hack.
    // We should most likely take a client here.
    globalHttpClient.close();
  }
}

class ResolutionFailedException implements Exception {
  String message;
  ResolutionFailedException._(this.message);
}

/// Given a Git repo that contains a pub package, gets the name of the pub
/// package.
///
/// Will download the repo to the system cache under the assumption that the
/// package will be downloaded afterwards.
///
/// [url] points to the git repository. If it is a relative url, it is resolved
/// as a file url relative to the path [relativeTo].
///
/// [ref] is the commit-hash where the package should be looked up when fetching
/// the name. If omitted, 'HEAD' is used.
///
/// [tagPattern] is a string containing `'{{version}}'` as a substring, the
/// latest tag matching the pattern will be used for fetching the name.
///
/// Only one of [ref] and [tagPattern] can be used.
///
/// If [isOffline], only the already cached versions of the repo is used.
Future<String> getPackageNameFromGitRepo(
  String url, {
  String? ref,
  String? path,
  String? tagPattern,
  String? relativeTo,
  bool isOffline = false,
}) async {
  return await GitSource.instance.getPackageNameFromRepo(
    url,
    ref,
    path,
    SystemCache(isOffline: isOffline),
    relativeTo: relativeTo,
    tagPattern: tagPattern,
  );
}
