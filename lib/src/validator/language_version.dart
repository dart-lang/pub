// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:stack_trace/stack_trace.dart';

import '../dart.dart';
import '../entrypoint.dart';
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
    final sdkConstraint = entrypoint.root.pubspec.originalDartSdkConstraint;

    /// If the sdk constraint is not a `VersionRange` something is wrong, and
    /// we cannot deduce the language version.
    ///
    /// This will hopefully be detected elsewhere.
    ///
    /// A single `Version` is also a `VersionRange`.
    if (sdkConstraint is! VersionRange) return;

    final packageSdkMinVersion = (sdkConstraint as VersionRange).min;
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

      final unitLanguageVersion = unit.languageVersionToken;
      if (unitLanguageVersion != null) {
        if (Version(unitLanguageVersion.major, unitLanguageVersion.minor, 0) >
            packageSdkMinVersion) {
          final packageLanguageVersionString =
              '${packageSdkMinVersion.major}.${packageSdkMinVersion.minor}';
          final unitLanguageVersionString =
              '${unitLanguageVersion.major}.${unitLanguageVersion.minor}';
          final relativePath = p.relative(path);
          errors.add('$relativePath is declaring language version '
              '$unitLanguageVersionString that is newer than the SDK '
              'constraint $packageLanguageVersionString declared in '
              '`pubspec.yaml`.');
        }
      }
    }
  }
}
