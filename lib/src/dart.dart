// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A library for compiling Dart code and manipulating analyzer parse trees.
import 'dart:async';
import 'dart:io';

import 'package:analyzer/dart/analysis/context_builder.dart';
import 'package:analyzer/dart/analysis/context_locator.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/error.dart';
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
      : _session = ContextBuilder()
            .createContext(
              contextRoot: ContextLocator().locateRoots(
                includedPaths: [p.absolute(p.normalize(packagePath))],
                optionsFile:
                    // We don't want to take 'analysis_options.yaml' files into
                    // account. So we replace it with an empty file.
                    Platform.isWindows ? r'C:\NUL' : '/dev/null',
              ).first,
            )
            .currentSession;

  /// Parse the file with the given [path] into AST.
  ///
  /// One of the containing directories must be used to create analysis
  /// contexts using [createContextsForDirectory]. Throws [StateError] if
  /// this has not been done.
  ///
  /// Throws [AnalyzerErrorGroup] is the file has parsing errors.
  CompilationUnit parse(String path) {
    path = p.normalize(p.absolute(path));
    var parseResult = _session.getParsedUnit(path);
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
    var unit = parse(path);
    var uriDirectives = <UriBasedDirective>[];
    for (var directive in unit.directives) {
      if (directive is UriBasedDirective) {
        uriDirectives.add(directive);
      }
    }
    return uriDirectives;
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
///
/// The [additionalSources], if provided, instruct the compiler to include
/// additional source files into compilation even if they are not referenced
/// from the main library.
///
/// The [nativeAssets], if provided, instruct the compiler include a native
/// assets map.
Future<void> precompile({
  required String executablePath,
  required String incrementalDillPath,
  required String name,
  required String outputPath,
  required String packageConfigPath,
  List<String> additionalSources = const [],
  String? nativeAssets,
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
        p.join(tempDir, '${p.basename(incrementalDillPath)}.temp');
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
      additionalSources: additionalSources,
      nativeAssets: nativeAssets,
      printIncrementalDependencies: false,
    );
    final result = await client.compile();

    final highlightedName = log.bold(name);
    if (result.errorCount == 0) {
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
