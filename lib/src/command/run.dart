// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:path/path.dart' as p;

import '../command.dart';
import '../executable.dart';
import '../io.dart';
import '../log.dart' as log;
import '../utils.dart';

/// Handles the `run` pub command.
class RunCommand extends PubCommand {
  String get name => 'run';
  String get description => 'Run an executable from a package.';
  String get invocation => 'pub run <executable> [args...]';
  String get docUrl => "https://dart.dev/tools/pub/cmd/pub-run";
  bool get allowTrailingOptions => false;

  RunCommand() {
    argParser.addFlag('enable-asserts', help: 'Enable assert statements.');
    argParser.addFlag('checked', abbr: 'c', hide: true);
    argParser.addOption('mode', help: 'Deprecated option', hide: true);
  }

  Future run() async {
    if (argResults.rest.isEmpty) {
      usageException('Must specify an executable to run.');
    }

    var package = entrypoint.root.name;
    var executable = argResults.rest[0];
    var args = argResults.rest.skip(1).toList();

    // A command like "foo:bar" runs the "bar" script from the "foo" package.
    // If there is no colon prefix, default to the root package.
    if (executable.contains(':')) {
      var components = split1(executable, ':');
      package = components[0];
      executable = components[1];

      if (p.split(executable).length > 1) {
        usageException(
            'Cannot run an executable in a subdirectory of a dependency.');
      }
    } else if (onlyIdentifierRegExp.hasMatch(executable)) {
      // "pub run foo" means the same thing as "pub run foo:foo" as long as
      // "foo" is a valid Dart identifier (and thus package name).
      package = executable;
    }

    if (argResults.wasParsed('mode')) {
      log.warning('The --mode flag is deprecated and has no effect.');
    }

    // The user may pass in an executable without an extension, but the file
    // to actually execute will always have one.
    if (p.extension(executable) != '.dart') executable += '.dart';

    var snapshotPath = p.join(
        entrypoint.cachePath, 'bin', package, '$executable.snapshot.dart2');

    // Don't ever compile snapshots for mutable packages, since their code may
    // change later on.
    var useSnapshot = fileExists(snapshotPath) ||
        (package != entrypoint.root.name &&
            !entrypoint.packageGraph.isPackageMutable(package));

    final executablePath = entrypoint.packageGraph.packages[package]
        ?.path(p.join("bin", executable));

    var exitCode = await runExecutable(entrypoint, package, executable, args,
        checked: argResults['enable-asserts'] || argResults['checked'],
        snapshotPath: useSnapshot ? snapshotPath : null,
        recompile: () =>
            entrypoint.precompileExecutable(package, executablePath));
    await flushThenExit(exitCode);
  }
}
