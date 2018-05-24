// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A library for compiling Dart code and manipulating analyzer parse trees.
import 'dart:async';
import 'dart:io';

import 'package:analyzer/analyzer.dart';

import 'exceptions.dart';
import 'io.dart';
import 'log.dart' as log;
import 'utils.dart';

/// Returns whether [dart] looks like an entrypoint file.
bool isEntrypoint(CompilationUnit dart) {
  // Allow two or fewer arguments so that entrypoints intended for use with
  // [spawnUri] get counted.
  //
  // TODO(nweiz): this misses the case where a Dart file doesn't contain main(),
  // but it parts in another file that does.
  return dart.declarations.any((node) {
    return node is FunctionDeclaration &&
        node.name.name == "main" &&
        node.functionExpression.parameters.parameters.length <= 2;
  });
}

/// Efficiently parses the import and export directives in [contents].
///
/// If [name] is passed, it's used as the filename for error reporting.
List<UriBasedDirective> parseImportsAndExports(String contents, {String name}) {
  var collector = new _DirectiveCollector();
  parseDirectives(contents, name: name).accept(collector);
  return collector.directives;
}

/// A simple visitor that collects import and export nodes.
class _DirectiveCollector extends GeneralizingAstVisitor {
  final directives = <UriBasedDirective>[];

  visitUriBasedDirective(UriBasedDirective node) => directives.add(node);
}

/// Snapshots the Dart executable at [executableUrl] to a snapshot at
/// [snapshotPath].
///
/// If [packagesFile] is passed, it's used to resolve `package:` URIs in the
/// executable. Otherwise, a `packages/` directory or a package spec is inferred
/// from the executable's location.
///
/// If [name] is passed, it is used to describe the executable in logs and error
/// messages.
///
/// When running in Dart 2 mode, this automatically creates a Dart 2-compatible
/// snapshot as well at `$snapshotPath.dart2`.
Future snapshot(Uri executableUrl, String snapshotPath,
    {Uri packagesFile, String name}) async {
  name = log.bold(name ?? executableUrl.toString());

  var dart1Args = ['--snapshot=$snapshotPath', executableUrl.toString()];

  var dart2Path = '$snapshotPath.dart2';
  var dart2Args = isDart2
      ? ['--preview-dart-2', '--snapshot=$dart2Path', executableUrl.toString()]
      : null;

  if (packagesFile != null) {
    dart1Args.insert(0, "--packages=$packagesFile");

    // Resolve [packagesFile] in case it's relative to work around sdk#33177.
    dart2Args?.insert(0, "--packages=${Uri.base.resolveUri(packagesFile)}");
  }

  var processes = [runProcess(Platform.executable, dart1Args)];
  if (isDart2) processes.add(runProcess(Platform.executable, dart2Args));
  var results = await Future.wait(processes);

  var failure =
      results.firstWhere((result) => !result.success, orElse: () => null);
  if (failure == null) {
    log.message("Precompiled $name.");
  } else {
    // Don't leave partial results.
    deleteEntry(snapshotPath);
    deleteEntry(dart2Path);

    throw new ApplicationException(log.yellow("Failed to precompile $name:\n") +
        failure.stderr.join('\n'));
  }
}
