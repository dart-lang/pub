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

/// Returns whether [dart] contains a [PartOfDirective].
bool isPart(CompilationUnit dart) =>
    dart.directives.any((directive) => directive is PartOfDirective);

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

/// Runs [code] in an isolate.
///
/// [code] should be the contents of a Dart entrypoint. It may contain imports;
/// they will be resolved in the same context as the host isolate. [message] is
/// passed to the [main] method of the code being run; the caller is responsible
/// for using this to establish communication with the isolate.
///
/// [packageRoot] controls the package root of the isolate. It may be either a
/// [String] or a [Uri].
///
/// If [snapshot] is passed, the isolate will be loaded from that path if it
/// exists. Otherwise, a snapshot of the isolate's code will be saved to that
/// path once the isolate is loaded.
Future runInIsolate(String code, message,
    {packageRoot, String snapshot}) async {
  if (snapshot != null && fileExists(snapshot)) {
    log.fine("Spawning isolate from $snapshot.");
    if (packageRoot != null) packageRoot = Uri.parse(packageRoot.toString());
    try {
      // Make the snapshot URI absolute to work around sdk#8440.
      await Isolate.spawnUri(p.toUri(p.absolute(snapshot)), [], message,
          packageRoot: packageRoot);
      return;
    } on IsolateSpawnException catch (error) {
      log.fine("Couldn't load existing snapshot $snapshot:\n$error");
      // Do nothing, we will regenerate the snapshot below.
    }
  }

  await withTempDir((dir) async {
    var dartPath = p.join(dir, 'runInIsolate.dart');
    writeTextFile(dartPath, code, dontLogContents: true);
    await Isolate.spawnUri(p.toUri(p.absolute(dartPath)), [], message,
        packageRoot: packageRoot);

    if (snapshot == null) return;

    ensureDir(p.dirname(snapshot));
    var snapshotArgs = <String>[];
    if (packageRoot != null) snapshotArgs.add('--package-root=$packageRoot');
    snapshotArgs.addAll(['--snapshot=$snapshot', dartPath]);
    var result = await runProcess(Platform.executable, snapshotArgs);

    if (result.success) return;

    // Don't emit a fatal error here, since we don't want to crash the
    // otherwise successful isolate load.
    log.warning("Failed to compile a snapshot to "
        "${p.relative(snapshot)}:\n" +
        result.stderr.join("\n"));
  });
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
