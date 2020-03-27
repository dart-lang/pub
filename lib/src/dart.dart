// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A library for compiling Dart code and manipulating analyzer parse trees.
import 'dart:async';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:analyzer/file_system/overlay_file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer/dart/analysis/context_builder.dart';
import 'package:analyzer/dart/analysis/context_locator.dart';
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/error.dart';
import 'package:path/path.dart' as p;

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
        node.name.name == 'main' &&
        node.functionExpression.parameters.parameters.length <= 2;
  });
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
Future snapshot(Uri executableUrl, String snapshotPath,
    {Uri packagesFile, String name}) async {
  name = log.bold(name ?? executableUrl.toString());

  var args = ['--snapshot=$snapshotPath', executableUrl.toString()];

  if (packagesFile != null) {
    // Resolve [packagesFile] in case it's relative to work around sdk#33177.
    args.insert(0, '--packages=${Uri.base.resolveUri(packagesFile)}');
  }

  var result = await runProcess(Platform.executable, args);
  if (result.success) {
    log.message('Precompiled $name.');
  } else {
    // Don't leave partial results.
    deleteEntry(snapshotPath);

    throw ApplicationException(
        log.yellow('Failed to precompile $name:\n') + result.stderr.join('\n'));
  }
}

class AnalysisContextManager {
  /// The map from a context root directory to to the context.
  final Map<String, AnalysisContext> _contexts = {};

  /// Ensure that there are analysis contexts for the directory with the
  /// given [path]. If any previously added root covers the [path], keep
  /// the previously created analysis context.
  ///
  /// This method does not discover analysis roots "up", it only looks down
  /// the given [path]. It is expected that the client knows analysis roots
  /// in advance. Pub does know, it is the packages it works with.
  void createContextsForDirectory(String path) {
    path = p.normalize(p.absolute(path));

    // We add all contexts below the given directory.
    // So, children contexts must also have been added.
    if (_contexts.containsKey(path)) {
      return;
    }

    // Overwrite the analysis_options.yaml to avoid loading the file included
    // in the package, as this may result in some files not being analyzed.
    final resourceProvider =
        OverlayResourceProvider(PhysicalResourceProvider.INSTANCE);
    resourceProvider.setOverlay(
      p.join(path, 'analysis_options.yaml'),
      content: '',
      modificationStamp: 0,
    );

    // Add new contexts for the given path.
    var contextLocator = ContextLocator(resourceProvider: resourceProvider);
    var roots = contextLocator.locateRoots(includedPaths: [path]);
    for (var root in roots) {
      var contextRootPath = root.root.path;

      // If there is already a context for this context root path, keep it.
      if (_contexts.containsKey(contextRootPath)) {
        continue;
      }

      var contextBuilder = ContextBuilder();
      var context = contextBuilder.createContext(contextRoot: root);
      _contexts[contextRootPath] = context;
    }
  }

  /// Parse the file with the given [path] into AST.
  ///
  /// One of the containing directories must be used to create analysis
  /// contexts using [createContextsForDirectory]. Throws [StateError] if
  /// this has not been done.
  ///
  /// Throws [AnalyzerErrorGroup] is the file has parsing errors.
  CompilationUnit parse(String path) {
    path = p.normalize(p.absolute(path));
    var parseResult = _getExistingSession(path).getParsedUnit(path);
    if (parseResult.errors.isNotEmpty) {
      throw AnalyzerErrorGroup(parseResult.errors);
    }
    return parseResult.unit;
  }

  /// Return import and export directives in the file with the given [path].
  ///
  /// One of the containing directories must be used to create analysis
  /// contexts using [createContextsForDirectory]. Throws [StateError] if
  /// this has not been done.
  ///
  /// Throws [AnalyzerErrorGroup] is the file has parsing errors.
  List<UriBasedDirective> parseImportsAndExports(String path) {
    var unit = parse(path);
    var uriDirectives = <UriBasedDirective>[];
    for (var directive in unit.directives) {
      if (directive is UriBasedDirective) {
        uriDirectives.add(directive);
      }
    }
    return uriDirectives;
  }

  AnalysisSession _getExistingSession(String path) {
    for (var context in _contexts.values) {
      if (context.contextRoot.isAnalyzed(path)) {
        return context.currentSession;
      }
    }

    throw StateError('Unable to find the context to $path');
  }
}

/// An error class that contains multiple [AnalysisError]s.
class AnalyzerErrorGroup implements Exception {
  final List<AnalysisError> errors;

  AnalyzerErrorGroup(this.errors);

  String get message => toString();

  @override
  String toString() => errors.join('\n');
}
