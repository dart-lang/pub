// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A library for compiling Dart code and manipulating analyzer parse trees.
import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:analyzer/analyzer.dart';
import 'package:path/path.dart' as p;

import 'asset/id.dart';
import 'exceptions.dart';
import 'io.dart';
import 'log.dart' as log;

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
/// If [id] is passed, it's used to describe the executable in logs and error
/// messages.
Future snapshot(Uri executableUrl, String snapshotPath,
    {Uri packagesFile, AssetId id}) async {
  var name = log.bold(id == null
      ? executableUrl.toString()
      : "${id.package}:${p.url.basenameWithoutExtension(id.path)}");

  var args = ['--snapshot=$snapshotPath', executableUrl.toString()];
  if (packagesFile != null) args.insert(0, "--packages=$packagesFile");
  var result = await runProcess(Platform.executable, args);

  if (result.success) {
    log.message("Precompiled $name.");
  } else {
    throw new ApplicationException(
        log.yellow("Failed to precompile $name:\n") + result.stderr.join('\n'));
  }
}
