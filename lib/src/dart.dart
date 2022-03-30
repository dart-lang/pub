// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A library for compiling Dart code and manipulating analyzer parse trees.
import 'dart:async';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/file_system/overlay_file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:cli_util/cli_util.dart';
import 'package:frontend_server_client/frontend_server_client.dart';
import 'package:path/path.dart' as p;

import 'exceptions.dart';
import 'io.dart';
import 'log.dart' as log;

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

    var contextCollection = AnalysisContextCollection(
      includedPaths: [path],
      resourceProvider: resourceProvider,
      sdkPath: getSdkPath(),
    );

    // Add new contexts for the given path.
    for (var analysisContext in contextCollection.contexts) {
      var contextRootPath = analysisContext.contextRoot.root.path;

      // If there is already a context for this context root path, keep it.
      if (_contexts.containsKey(contextRootPath)) {
        continue;
      }

      _contexts[contextRootPath] = analysisContext;
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
    if (parseResult is ParsedUnitResult) {
      if (parseResult.errors.isNotEmpty) {
        throw AnalyzerErrorGroup(parseResult.errors);
      }
      return parseResult.unit;
    } else {
      throw StateError('Unable to parse $path, ${parseResult.runtimeType}');
    }
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

/// Precompiles the Dart executable at [executablePath].
///
/// If the compilation succeeds it is saved to a kernel file at [outputPath].
///
/// If compilation fails, the output is cached at [incrementalDillOutputPath].
///
/// Whichever of [incrementalDillOutputPath] and [outputPath] already exists is
/// used to initialize the compiler run.
///
/// The [packageConfigPath] should point at the package config file to be used
/// for `package:` uri resolution.
///
/// The [name] is used to describe the executable in logs and error messages.
Future<void> precompile({
  required String executablePath,
  required String incrementalDillPath,
  required String name,
  required String outputPath,
  required String packageConfigPath,
}) async {
  ensureDir(p.dirname(outputPath));
  ensureDir(p.dirname(incrementalDillPath));

  const platformDill = 'lib/_internal/vm_platform_strong.dill';
  final sdkRoot = p.relative(p.dirname(p.dirname(Platform.resolvedExecutable)));
  String? tempDir;
  FrontendServerClient? client;
  try {
    tempDir = createTempDir(p.dirname(incrementalDillPath), 'tmp');
    // To avoid potential races we copy the incremental data to a temporary file
    // for just this compilation.
    final temporaryIncrementalDill =
        p.join(tempDir, '${p.basename(incrementalDillPath)}.incremental.dill');
    try {
      if (fileExists(incrementalDillPath)) {
        copyFile(incrementalDillPath, temporaryIncrementalDill);
      } else if (fileExists(outputPath)) {
        copyFile(outputPath, temporaryIncrementalDill);
      }
    } on FileSystemException {
      // Not able to copy existing file, compilation will start from scratch.
    }

    client = await FrontendServerClient.start(
      executablePath,
      temporaryIncrementalDill,
      platformDill,
      sdkRoot: sdkRoot,
      packagesJson: packageConfigPath,
      printIncrementalDependencies: false,
    );
    final result = await client.compile();

    final highlightedName = log.bold(name);
    if (result?.errorCount == 0) {
      log.message('Built $highlightedName.');
      // By using rename we ensure atomicity. An external observer will either
      // see the old or the new snapshot.
      renameFile(temporaryIncrementalDill, outputPath);
    } else {
      // By using rename we ensure atomicity. An external observer will either
      // see the old or the new snapshot.
      renameFile(temporaryIncrementalDill, incrementalDillPath);
      // If compilation failed we don't want to leave an incorrect snapshot.
      tryDeleteEntry(outputPath);

      throw ApplicationException(
          log.yellow('Failed to build $highlightedName:\n') +
              (result?.compilerOutputLines.join('\n') ?? ''));
    }
  } finally {
    client?.kill();
    if (tempDir != null) {
      tryDeleteEntry(tempDir);
    }
  }
}
