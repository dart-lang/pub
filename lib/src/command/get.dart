// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../command.dart';
import '../io.dart';
import '../log.dart' as log;
// import '../pubspec.dart';
import '../solver.dart';
import '../source/sdk.dart';
// import '../system_cache.dart';

/// Handles the `get` pub command.
class GetCommand extends PubCommand {
  @override
  String get name => 'get';
  @override
  String get description => "Get the current package's dependencies.";
  @override
  String get docUrl => 'https://dart.dev/tools/pub/cmd/pub-get';
  @override
  bool get isOffline => argResults['offline'];

  GetCommand() {
    argParser.addFlag(
      'offline',
      help: 'Use cached packages instead of accessing the network.',
    );

    argParser.addFlag(
      'dry-run',
      abbr: 'n',
      negatable: false,
      help: "Report what dependencies would change but don't change any.",
    );

    argParser.addFlag(
      'enforce-lockfile',
      negatable: false,
      help:
          'Enforce pubspec.lock. Fail resolution if pubspec.lock does not satisfy pubspec.yaml',
    );

    argParser.addFlag(
      'precompile',
      help: 'Build executables in immediate dependencies.',
    );

    argParser.addFlag('packages-dir', hide: true);

    argParser.addFlag(
      'example',
      help: 'Also run in `example/` (if it exists).',
      hide: true,
    );

    argParser.addOption(
      'directory',
      abbr: 'C',
      help: 'Run this in the directory<dir>.',
      valueHelp: 'dir',
    );
  }

  bool shouldRunPostGetHook() {
    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    if (flutterRoot == null) {
      return false;
    }
    if (!fileExists(p.join(flutterRoot, 'version'))) {
      return false;
    }

    // TODO: sky_engine check
    final hasFlutterDependency =
        entrypoint.root.dependencies.values.any((package) {
      return package.name == 'flutter' &&
          package.source.runtimeType == SdkSource;
    });

    return hasFlutterDependency;
  }

  Future<int> runPostGetHook() async {
    final String flutterRoot = Platform.environment['FLUTTER_ROOT']!;
    final String flutterToolPath = p.join(flutterRoot, 'bin', 'flutter');

    final StreamSubscription<ProcessSignal> subscription =
        ProcessSignal.sigint.watch().listen((e) {});
    final Process process = await Process.start(
      flutterToolPath,
      [
        'pub',
        '_post_pub_get',
        '-C',
        directory,
        '--update-version-and-package-config',
        '--regenerate-platform-specific-tooling',
        argResults['example'] ? '--example' : '',
      ],
      mode: ProcessStartMode.inheritStdio,
    );

    final int exitCode = await process.exitCode;
    await subscription.cancel();
    return exitCode;
  }

  @override
  Future<void> runProtected() async {
    if (argResults.wasParsed('packages-dir')) {
      log.warning(
        log.yellow(
          'The --packages-dir flag is no longer used and does nothing.',
        ),
      );
    }

    await entrypoint.acquireDependencies(
      SolveType.get,
      dryRun: argResults['dry-run'],
      precompile: argResults['precompile'],
      analytics: analytics,
      enforceLockfile: argResults['enforce-lockfile'],
    );

    if (!argResults['dry-run'] && shouldRunPostGetHook()) {
      log.message('Running post get hook...');
      final exitCode = await runPostGetHook();
      log.message('exit code: $exitCode');
    }

    var example = entrypoint.example;
    if (argResults['example'] && example != null) {
      await example.acquireDependencies(
        SolveType.get,
        dryRun: argResults['dry-run'],
        precompile: argResults['precompile'],
        analytics: analytics,
        summaryOnly: true,
        enforceLockfile: argResults['enforce-lockfile'],
      );
    }
  }
}
