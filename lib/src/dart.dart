// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A library for compiling Dart code and manipulating analyzer parse trees.
library;

import 'dart:async';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:frontend_server_client/frontend_server_client.dart';
import 'package:path/path.dart' as p;

import 'exceptions.dart';
import 'io.dart';
import 'log.dart' as log;

class AnalysisContextManager {
  static final sessions = <String, AnalysisContextManager>{};

  final String packagePath;
  final AnalysisSession _session;

  factory AnalysisContextManager(String packagePath) => sessions.putIfAbsent(
    packagePath,
    () => AnalysisContextManager._(packagePath),
  );

  AnalysisContextManager._(this.packagePath)
    : _session =
          AnalysisContextCollection(
            includedPaths: [packagePath],
          ).contextFor(packagePath).currentSession;

  /// Parse the file with the given [path] into AST.
  ///
  /// One of the containing directories must have been used to create `this`.
  /// Throws [StateError] otherwise.
  ///
  /// Throws [AnalyzerErrorGroup] is the file has parsing errors.
  CompilationUnit parse(String path) {
    path = p.normalize(p.absolute(path));
    final parseResult = _session.getParsedUnit(path);
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
  /// Throws [AnalyzerErrorGroup] is the file has parsing errors.
  List<UriBasedDirective> parseImportsAndExports(String path) {
    final unit = parse(path);
    final uriDirectives = <UriBasedDirective>[];
    for (var directive in unit.directives) {
      if (directive is UriBasedDirective) {
        uriDirectives.add(directive);
      }
    }
    return uriDirectives;
  }
}

/// An error class that contains multiple [Diagnostic]s.
class AnalyzerErrorGroup implements Exception {
  final List<Diagnostic> errors;

  AnalyzerErrorGroup(this.errors);

  String get message => toString();

  @override
  String toString() => errors.join('\n');
}

/// Precompiles the Dart executable at [executablePath].
///
/// If the compilation succeeds it is saved to a kernel file at [outputPath].
///
/// If compilation fails, the output is cached at "[outputPath].incremental".
///
/// Whichever of "[outputPath].incremental" and [outputPath] already exists is
/// used to initialize the compiler run. To avoid the potential for
/// race-conditions, it is first copied to a temporary location, and atomically
/// moved to either [outputPath] or "[outputPath].incremental" depending on the
/// result of compilation.
///
/// The [packageConfigPath] should point at the package config file to be used
/// for `package:` uri resolution.
///
/// The [name] is used to describe the executable in logs and error messages.
///
/// The [additionalSources], if provided, instruct the compiler to include
/// additional source files into compilation even if they are not referenced
/// from the main library.
///
/// The [nativeAssets], if provided, instruct the compiler include a native
/// assets map.
Future<void> precompile({
  required String executablePath,
  required String name,
  required String outputPath,
  required String packageConfigPath,
  List<String> additionalSources = const [],
  String? nativeAssets,
}) async {
  const platformDill = 'lib/_internal/vm_platform_strong.dill';
  final sdkRoot = p.relative(p.dirname(p.dirname(Platform.resolvedExecutable)));
  String? tempDir;
  FrontendServerClient? client;
  try {
    ensureDir(p.dirname(outputPath));
    final incrementalDillPath = '$outputPath.incremental';
    tempDir = createTempDir(p.dirname(outputPath), 'tmp');
    // To avoid potential races we copy the incremental data to a temporary file
    // for just this compilation.
    final temporaryIncrementalDill = p.join(
      tempDir,
      '${p.basename(incrementalDillPath)}.temp',
    );
    try {
      if (fileExists(outputPath)) {
        copyFile(outputPath, temporaryIncrementalDill);
      } else if (fileExists(incrementalDillPath)) {
        copyFile(incrementalDillPath, temporaryIncrementalDill);
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
      additionalSources: additionalSources,
      nativeAssets: nativeAssets,
      printIncrementalDependencies: false,
    );
    final result = await client.compile();

    // Sanity check. We've had reports of the compilation failing to provide a
    // result, perhaps due to low-memory conditions.
    // This should make this slightly easier to recognize in error reports.
    if (!fileExists(temporaryIncrementalDill)) {
      log.error(
        'Compilation did not produce any result. '
        'Expected file at `$temporaryIncrementalDill`',
        result.dillOutput,
      );
    }

    final highlightedName = log.bold(name);
    if (result.errorCount == 0) {
      log.message('Built $highlightedName.');
      // By using rename we ensure atomicity. An external observer will either
      // see the old or the new snapshot.
      renameFile(temporaryIncrementalDill, outputPath);
      // Any old incremental data is deleted in case we started from a file on
      // [incrementalDillPath].
      deleteEntry(incrementalDillPath);
    } else {
      // By using rename we ensure atomicity. An external observer will either
      // see the old or the new snapshot.
      renameFile(temporaryIncrementalDill, incrementalDillPath);
      // If compilation failed, don't leave an incorrect snapshot.
      tryDeleteEntry(outputPath);

      throw ApplicationException(
        log.yellow('Failed to build $highlightedName:\n') +
            result.compilerOutputLines.join('\n'),
      );
    }
  } finally {
    client?.kill();
    if (tempDir != null) {
      tryDeleteEntry(tempDir);
    }
  }
}
