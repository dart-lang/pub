// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:yaml/yaml.dart';

import '../io.dart';
import '../path.dart';
import '../validator.dart';

/// Validates that `analysis_options.yaml` (and other analysis options files)
/// do not include configuration from a local file outside the package.
///
/// Including files outside the package causes analysis errors on `pub.dev`
/// and for consumers because those external files are not included in the
/// published archive.
final class AnalysisOptionsValidator extends Validator {
  @override
  Future<void> validate() async {
    final candidates = <String>{
      if (fileExists(p.join(package.dir, 'analysis_options.yaml')))
        p.canonicalize(p.join(package.dir, 'analysis_options.yaml')),
      if (fileExists(p.join(package.dir, '.analysis_options')))
        p.canonicalize(p.join(package.dir, '.analysis_options')),
      for (final file in files)
        if (p.basename(file) == 'analysis_options.yaml' ||
            p.basename(file) == '.analysis_options')
          p.canonicalize(file),
    };

    final visited = <String>{};
    for (final candidate in candidates) {
      _validateAnalysisOptionsFile(candidate, visited);
    }
  }

  void _validateAnalysisOptionsFile(String filePath, Set<String> visited) {
    if (!visited.add(filePath)) return;
    if (!fileExists(filePath)) return;

    final String contents;
    try {
      contents = readTextFile(filePath);
    } on IOException {
      return;
    }

    final Object? yaml;
    try {
      yaml = loadYaml(contents);
    } on FormatException {
      return;
    }

    if (yaml is! Map) return;

    final include = yaml['include'];
    final includes = <String>[];
    if (include is String) {
      includes.add(include);
    } else if (include is YamlScalar && include.value is String) {
      includes.add(include.value as String);
    } else if (include is List) {
      for (final item in include) {
        if (item is String) {
          includes.add(item);
        } else if (item is YamlScalar && item.value is String) {
          includes.add(item.value as String);
        }
      }
    }

    final packageDir = p.canonicalize(package.dir);

    for (final includeUri in includes) {
      final parsedUri = Uri.tryParse(includeUri);
      if (parsedUri != null && parsedUri.scheme == 'package') {
        continue;
      }

      final String targetPath;
      if (parsedUri != null && parsedUri.scheme == 'file') {
        targetPath = p.canonicalize(p.fromUri(parsedUri));
      } else if (parsedUri != null &&
          parsedUri.hasScheme &&
          parsedUri.scheme != 'file') {
        continue;
      } else if (p.isAbsolute(includeUri)) {
        targetPath = p.canonicalize(includeUri);
      } else {
        targetPath = p.canonicalize(p.join(p.dirname(filePath), includeUri));
      }

      final isInsidePackage =
          p.isWithin(packageDir, targetPath) ||
          p.equals(packageDir, targetPath);

      if (!isInsidePackage) {
        final relOptionsPath = p.relative(filePath, from: package.dir);
        warnings.add(
          'The analysis options file `$relOptionsPath` includes '
          '`$includeUri`, which points to a file outside the package.\n'
          'Files outside the package are not included in the published '
          'package.\n\n'
          'Consider using a package URI (e.g. `package:lints/recommended.yaml`) '
          'or inlining the options.',
        );
      } else if (fileExists(targetPath)) {
        _validateAnalysisOptionsFile(targetPath, visited);
      }
    }
  }
}
