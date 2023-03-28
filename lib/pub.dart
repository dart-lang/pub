// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:args/command_runner.dart';

import 'src/entrypoint.dart';
import 'src/exceptions.dart';
import 'src/pub_embeddable_command.dart';
import 'src/system_cache.dart';

export 'src/executable.dart'
    show
        getExecutableForCommand,
        CommandResolutionFailedException,
        CommandResolutionIssue,
        DartExecutableWithPackageConfig;
export 'src/pub_embeddable_command.dart' show PubAnalytics;

/// Returns a [Command] for pub functionality that can be used by an embedding
/// CommandRunner.
///
/// If [analytics] is given, pub will use that analytics instance to send
/// statistics about resolutions.
///
/// [isVerbose] should return `true` (after argument resolution) if the
/// embedding top-level is in verbose mode.
Command<int> pubCommand({
  PubAnalytics? analytics,
  required bool Function() isVerbose,
}) =>
    PubEmbeddableCommand(analytics, isVerbose);

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
  PubAnalytics? analytics,
  bool isOffline = false,
  bool checkForSdkUpdate = false,
  bool summaryOnly = true,
  bool onlyOutputWhenTerminal = true,
}) async {
  try {
    await Entrypoint(dir, SystemCache(isOffline: isOffline)).ensureUpToDate(
      analytics: analytics,
      checkForSdkUpdate: checkForSdkUpdate,
      summaryOnly: summaryOnly,
      onlyOutputWhenTerminal: onlyOutputWhenTerminal,
    );
  } on ApplicationException catch (e) {
    throw ResolutionFailedException._(e.toString());
  }
}

class ResolutionFailedException implements Exception {
  String message;
  ResolutionFailedException._(this.message);
}
