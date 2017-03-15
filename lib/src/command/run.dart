// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:barback/barback.dart';
import 'package:path/path.dart' as p;

import '../command.dart';
import '../executable.dart';
import '../io.dart';
import '../utils.dart';

/// Handles the `run` pub command.
class RunCommand extends PubCommand {
  String get name => "run";
  String get description => "Run an executable from a package.";
  String get invocation => "pub run <executable> [args...]";
  bool get allowTrailingOptions => false;

  RunCommand() {
    argParser.addFlag("checked",
        abbr: "c", help: "Enable runtime type checks and assertions.");
    argParser.addOption("mode",
        help: 'Mode to run transformers in.\n'
            '(defaults to "release" for dependencies, "debug" for '
            'entrypoint)');
  }

  Future run() async {
    if (argResults.rest.isEmpty) {
      usageException("Must specify an executable to run.");
    }

    var package = entrypoint.root.name;
    var executable = argResults.rest[0];
    var args = argResults.rest.skip(1).toList();

    // A command like "foo:bar" runs the "bar" script from the "foo" package.
    // If there is no colon prefix, default to the root package.
    if (executable.contains(":")) {
      var components = split1(executable, ":");
      package = components[0];
      executable = components[1];

      if (p.split(executable).length > 1) {
        // TODO(nweiz): Use adjacent strings when the new async/await compiler
        // lands.
        usageException(
            "Cannot run an executable in a subdirectory of a " + "dependency.");
      }
    } else if (onlyIdentifierRegExp.hasMatch(executable)) {
      // "pub run foo" means the same thing as "pub run foo:foo" as long as
      // "foo" is a valid Dart identifier (and thus package name).
      package = executable;
    }

    var mode;
    if (argResults['mode'] != null) {
      mode = new BarbackMode(argResults['mode']);
    } else if (package == entrypoint.root.name) {
      mode = BarbackMode.DEBUG;
    } else {
      mode = BarbackMode.RELEASE;
    }

    var exitCode = await runExecutable(entrypoint, package, executable, args,
        checked: argResults['checked'], mode: mode);
    await flushThenExit(exitCode);
  }
}
