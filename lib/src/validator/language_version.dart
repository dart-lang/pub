// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;
import 'package:stack_trace/stack_trace.dart';

import '../dart.dart';
import '../entrypoint.dart';
import '../language_version.dart';
import '../log.dart' as log;
import '../utils.dart';
import '../validator.dart';

/// Validates that libraries do not opt into newer language versions than what
/// they declare in their pubspec.
class LanguageVersionValidator extends Validator {
  final AnalysisContextManager analysisContextManager =
      AnalysisContextManager();

  LanguageVersionValidator(Entrypoint entrypoint) : super(entrypoint) {
    var packagePath = p.normalize(p.absolute(entrypoint.root.dir));
    analysisContextManager.createContextsForDirectory(packagePath);
  }

  @override
  Future validate() async {
    final declaredLanguageVersion = entrypoint.root.pubspec.languageVersion;

    for (final path in ['lib', 'bin']
        .map((path) => entrypoint.root.listFiles(beneath: path))
        .expand((files) => files)
        .where((String file) => p.extension(file) == '.dart')) {
      CompilationUnit unit;
      try {
        unit = analysisContextManager.parse(path);
      } on AnalyzerErrorGroup catch (e, s) {
        // Ignore files that do not parse.
        log.fine(getErrorMessage(e));
        log.fine(Chain.forTrace(s).terse);
        continue;
      }

      final unitLanguageVersionToken = unit.languageVersionToken;
      if (unitLanguageVersionToken != null) {
        final unitLanguageVersion =
            LanguageVersion.fromLanguageVersionToken(unitLanguageVersionToken);
        if (unitLanguageVersion > declaredLanguageVersion) {
          final relativePath = p.relative(path);
          errors.add('$relativePath is declaring language version '
              '$unitLanguageVersion that is newer than the SDK '
              'constraint $declaredLanguageVersion declared in '
              '`pubspec.yaml`.');
        }
      }
    }
  }
}
