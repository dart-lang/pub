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
  @override
  String get name => 'run';
  @override
  String get description => 'Run an executable from a package.';
  @override
  String get invocation => 'pub run <executable> [args...]';
  @override
  String get docUrl => 'https://dart.dev/tools/pub/cmd/pub-run';
  @override
  bool get allowTrailingOptions => false;

  RunCommand() {
    argParser.addFlag('enable-asserts', help: 'Enable assert statements.');
    argParser.addFlag('checked', abbr: 'c', hide: true);
    argParser.addOption('mode', help: 'Deprecated option', hide: true);
    // mode exposed for `dartdev run` to use as subprocess.
    argParser.addFlag('v2', hide: true);
  }

  @override
  Future run() async {
    if (argResults['v2']) {
      return await _runV2();
    }
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

    var exitCode = await runExecutable(entrypoint, package, executable, args,
        enableAsserts: argResults['enable-asserts'] || argResults['checked'],
        snapshotPath: useSnapshot ? snapshotPath : null, recompile: () {
      final pkg = entrypoint.packageGraph.packages[package];
      // The recompile function will only be called when [package] exists.
      assert(pkg != null);
      final executablePath = pkg.path(p.join('bin', executable));
      return entrypoint.precompileExecutable(package, executablePath);
    });
    await flushThenExit(exitCode);
  }

  /// Implement a v2 mode for use in `dartdev run`.
  ///
  /// Usage: `dartdev run [package[:command]]`
  ///
  /// If `package` is not given, defaults to current root package.
  /// If `command` is not given, defaults to name of `package`.
  /// If neither `package` or `command` is given and `command` with name of
  /// the current package doesn't exist we fallback to `'main'`.
  ///
  /// Runs `bin/<command>.dart` from package `<package>`. If `<package>` is not
  /// mutable (local root package or path-dependency) a source snapshot will be
  /// cached in `.dart_tool/pub/bin/<package>/<command>.dart.snapshot.dart2`.
  Future _runV2() async {
    var package = entrypoint.root.name;
    var command = package;
    var args = <String>[];

    if (argResults.rest.isNotEmpty) {
      if (argResults.rest[0].contains(RegExp(r'[/\\]'))) {
        usageException('[<package>[:command]] cannot contain "/" or "\\"');
      }

      package = argResults.rest[0];
      if (package.contains(':')) {
        final parts = package.split(':');
        if (parts.length > 2) {
          usageException('[<package>[:command]] cannot contain multiple ":"');
        }
        package = parts[0];
        command = parts[1];
      } else {
        command = package;
      }
      args = argResults.rest.skip(1).toList();
    }

    String snapshotPath(String command) => p.join(
          entrypoint.cachePath,
          'bin',
          package,
          '$command.dart.snapshot.dart2',
        );

    // If snapshot exists, we strive to avoid using [entrypoint.packageGraph]
    // because this will load additional files. Instead we just run with the
    // snapshot. Note. that `pub get|upgrade` will purge snapshots.
    var snapshotExists = fileExists(snapshotPath(command));

    // Don't ever compile snapshots for mutable packages, since their code may
    // change later on. Don't check if this the case if a snapshot already
    // exists.
    var useSnapshot = snapshotExists ||
        (package != entrypoint.root.name &&
            !entrypoint.packageGraph.isPackageMutable(package));

    // If argResults.rest.isEmpty, package == command, and 'bin/$command.dart'
    // doesn't exist we use command = 'main' (if it exists).
    // We don't need to check this if a snapshot already exists.
    // This is a hack around the fact that we want 'dartdev run' to run either
    // `bin/<packageName>.dart` or `bin/main.dart`, because `bin/main.dart` is
    // a historical convention we've done in templates for a long time.
    if (!snapshotExists && argResults.rest.isEmpty && package == command) {
      final pkg = entrypoint.packageGraph.packages[package];
      if (pkg == null) {
        usageException('No such package "$package"');
      }
      if (!fileExists(pkg.path('bin', '$command.dart')) &&
          fileExists(pkg.path('bin', 'main.dart'))) {
        command = 'main';
        snapshotExists = fileExists(snapshotPath(command));
        useSnapshot = snapshotExists ||
            (package != entrypoint.root.name &&
                !entrypoint.packageGraph.isPackageMutable(package));
      }
    }

    return await flushThenExit(await runExecutable(
      entrypoint,
      package,
      '$command.dart',
      args,
      enableAsserts: argResults['enable-asserts'] || argResults['checked'],
      snapshotPath: useSnapshot ? snapshotPath(command) : null,
      recompile: () {
        final pkg = entrypoint.packageGraph.packages[package];
        // The recompile function will only be called when [package] exists.
        assert(pkg != null);
        return entrypoint.precompileExecutable(
          package,
          pkg.path('bin', '$command.dart'),
        );
      },
    ));
  }
}
